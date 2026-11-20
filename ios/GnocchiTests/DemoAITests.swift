import Foundation
import Testing
@testable import Gnocchi

@Suite("Demo-KI")
struct DemoAITests {
    @Test("Ignoriert Markdown und Modellnotizen vor und nach gültigem JSON")
    func extractsJSONWithSurroundingText() throws {
        let answer = ##"""
        Hier ist das Rezept:
        ```json
        {"title":"Pasta {mit \"Sugo\"}","steps":["Umrühren."]}
        ```
        Noch ein Hinweis zum Servieren.
        """##
        let json = try #require(JSONSerialization.jsonObject(with: DemoAI.jsonData(answer)) as? [String: Any])
        #expect(json["title"] as? String == "Pasta {mit \"Sugo\"}")
        #expect(json["steps"] as? [String] == ["Umrühren."])
    }

    @Test("Der Demo-Client verbindet sich mit dem ausgewählten Anbieter", arguments: DemoAI.Provider.allCases)
    func providerTransport(provider: DemoAI.Provider) async throws {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [DemoProviderFixture.self]
        let session = URLSession(configuration: settings)
        defer { session.invalidateAndCancel() }
        let config = DemoAI.Configuration(provider: provider, model: provider.defaultModel, key: "fixture-not-a-real-key")
        let text = try await DemoAI.generate(config, prompt: "Test", session: session)
        #expect(text == "OK")
    }

    @Test("Ein nicht abrufbarer Gemini-Link wird als solcher zurückgemeldet")
    func inaccessibleLink() async {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [DemoProviderFixture.self]
        let session = URLSession(configuration: settings)
        defer { session.invalidateAndCancel() }
        let config = DemoAI.Configuration(provider: .gemini, model: "unreadable-link", key: "fixture-not-a-real-key")
        await #expect(throws: DemoAI.Failure.unreadableURL) {
            try await DemoAI.generate(config, prompt: "Test", readURL: true, session: session)
        }
    }
}

private final class DemoProviderFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, request.httpMethod == "POST", url.query == nil else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let key = "fixture-not-a-real-key"
        let body: String
        switch url.host() {
        case "generativelanguage.googleapis.com" where request.value(forHTTPHeaderField: "x-goog-api-key") == key:
            if url.path.contains("unreadable-link") {
                body = #"{"candidates":[{"content":{"parts":[{"text":"OK"}]},"urlContextMetadata":{"urlMetadata":[{"urlRetrievalStatus":"URL_RETRIEVAL_STATUS_ERROR"}]}}]}"#
            } else {
                body = #"{"candidates":[{"content":{"parts":[{"thought":true,"text":"intern"},{"text":"OK"}]}}]}"#
            }
        case "api.anthropic.com" where request.value(forHTTPHeaderField: "x-api-key") == key:
            body = #"{"content":[{"text":"OK"}]}"#
        case "openrouter.ai" where request.value(forHTTPHeaderField: "Authorization") == "Bearer " + key:
            body = #"{"choices":[{"message":{"content":"OK"}}]}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
