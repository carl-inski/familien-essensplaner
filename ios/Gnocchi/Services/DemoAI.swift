import Foundation
import Security

enum DemoAI {
    enum Failure: Error { case unreadableURL }

    enum Provider: String, Codable, CaseIterable, Identifiable {
        case gemini = "Google Gemini"
        case anthropic = "Anthropic"
        case openRouter = "OpenRouter"

        var id: Self { self }
        var defaultModel: String {
            switch self {
            case .gemini: "gemini-3.8-flash"
            case .anthropic: "claude-haiku-5-5"
            case .openRouter: "google/gemini-3.8-flash"
            }
        }
    }

    struct Configuration: Codable {
        let provider: Provider
        let model: String
        let key: String

        var isValid: Bool {
            !key.isEmpty && key.count <= 1_024 && key.utf8.allSatisfy { (33...126).contains($0) }
                && model.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$"#, options: .regularExpression) != nil
                && (provider != .gemini || !model.contains("/") && !model.contains(":"))
        }
    }

    private static var keychainItem: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.gnocchi.ios.demo-ai",
         kSecAttrAccount as String: "provider-configuration"]
    }

    static var configuration: Configuration? {
        var query = keychainItem
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Configuration.self, from: data)
    }

    static func save(_ config: Configuration) throws {
        guard config.isValid else { throw AssistantFailure.message("Prüfe den API-Schlüssel und den Modellnamen.") }
        let data = try JSONEncoder().encode(config)
        let values = [kSecValueData as String: data]
        var status = SecItemUpdate(keychainItem as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = keychainItem
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AssistantFailure.message("Der Schlüssel konnte nicht gespeichert werden.") }
    }

    static func remove() throws {
        let status = SecItemDelete(keychainItem as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AssistantFailure.message("Der Schlüssel konnte nicht entfernt werden.")
        }
    }

    static func test(_ configuration: Configuration) async throws -> AssistantConnectionTest {
        let start = ContinuousClock.now
        _ = try await generate(configuration, prompt: "Antworte kurz mit OK.", maxTokens: 512)
        let time = start.duration(to: .now).components
        return AssistantConnectionTest(text: "Verbindung erfolgreich",
                                       ms: Double(time.seconds) * 1_000 + Double(time.attoseconds) / 1e15)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let direct = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    static func generate(_ config: Configuration, prompt: String, images: [String] = [],
                         json: Bool = false, readURL: Bool = false, maxTokens: Int = 4_096,
                         session: URLSession? = nil) async throws -> String {
        guard config.isValid else { throw AssistantFailure.message("Prüfe den API-Schlüssel und den Modellnamen.") }
        let textPart = ["type": "text", "text": prompt]
        let url: URL
        let payload: [String: Any]
        var headers: [String: String] = [:]

        switch config.provider {
        case .gemini:
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(config.model):generateContent")!
            headers["x-goog-api-key"] = config.key
            let parts: [[String: Any]] = [["text": prompt]] + images.map {
                ["inlineData": ["data": $0, "mimeType": "image/jpeg"]]
            }
            var settings: [String: Any] = ["maxOutputTokens": maxTokens]
            if json && !readURL { settings["responseMimeType"] = "application/json" }
            var requestBody: [String: Any] = ["contents": [["parts": parts]], "generationConfig": settings]
            if readURL { requestBody["tools"] = [["url_context": [String: String]()]] }
            payload = requestBody
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            headers = ["x-api-key": config.key, "anthropic-version": "2023-06-01"]
            let parts: [[String: Any]] = [textPart] + images.map {
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0]]
            }
            payload = ["model": config.model, "max_tokens": maxTokens, "messages": [["role": "user", "content": parts]]]
        case .openRouter:
            url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            headers["Authorization"] = "Bearer " + config.key
            let parts: [[String: Any]] = [textPart] + images.map {
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + $0]]
            }
            payload = ["model": config.model, "max_tokens": maxTokens, "messages": [["role": "user", "content": parts]]]
        }

        var request = URLRequest(url: url, timeoutInterval: 70)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        guard (request.httpBody?.count ?? 0) <= 8_000_000 else {
            throw AssistantFailure.message("Die Anfrage ist zu groß. Hänge weniger Fotos an oder starte einen neuen Chat.")
        }
        let (data, response) = try await (session ?? direct).data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            switch status {
            case 400, 401, 403: throw AssistantFailure.message("Der Anbieter hat die Anfrage abgelehnt. Prüfe Schlüssel, Modell und Zugriff.")
            case 402, 429: throw AssistantFailure.message("Das Guthaben oder Anfragelimit beim Anbieter ist erreicht.")
            case 404: throw AssistantFailure.message("Das Modell ist beim Anbieter nicht verfügbar.")
            default: throw AssistantFailure.message("Der KI-Anbieter ist gerade nicht erreichbar.")
            }
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        if readURL && reply.candidates?.first?.urlContextMetadata?.urlMetadata.contains(where: {
            $0.urlRetrievalStatus == "URL_RETRIEVAL_STATUS_SUCCESS"
        }) != true {
            throw Failure.unreadableURL
        }
        let parts = reply.candidates?.first?.content?.parts ?? reply.content
        let text = (reply.choices?.first?.message.content ?? parts?.filter { $0.thought != true }
            .compactMap(\.text).joined(separator: "\n") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AssistantFailure.message("Der KI-Anbieter hat keine Antwort geliefert.") }
        return text
    }

    static func jsonData(_ text: String) -> Data {
        let bytes = Array(text.utf8)
        var start: Int?
        var depth = 0
        var inString = false
        var escaped = false
        for (index, byte) in bytes.enumerated() {
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
                continue
            }
            switch byte {
            case 123, 91:
                if depth == 0 { start = index }
                depth += 1
            case 125 where depth > 0, 93 where depth > 0:
                depth -= 1
                if depth == 0, let start {
                    let candidate = Data(bytes[start...index])
                    if (try? JSONSerialization.jsonObject(with: candidate)) != nil { return candidate }
                }
            case 34 where depth > 0:
                inString = true
            default:
                break
            }
        }
        return Data(bytes)
    }

    private struct Reply: Decodable {
        struct Part: Decodable { let text: String?; let thought: Bool? }
        struct Content: Decodable { let parts: [Part] }
        struct Candidate: Decodable {
            struct URLContext: Decodable {
                struct Entry: Decodable { let urlRetrievalStatus: String }
                let urlMetadata: [Entry]
            }
            let content: Content?
            let urlContextMetadata: URLContext?
        }
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let candidates: [Candidate]?
        let content: [Part]?
        let choices: [Choice]?
    }
}
