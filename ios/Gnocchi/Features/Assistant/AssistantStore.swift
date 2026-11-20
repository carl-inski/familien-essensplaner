import Foundation
import GnocchiCore
import Observation
import Supabase

enum AssistantFailure: LocalizedError {
    case message(String)
    case planChanged
    var errorDescription: String? {
        switch self {
        case let .message(text): text
        case .planChanged: "Der Wochenplan hat sich geändert. Lass dir den Vorschlag erneut anzeigen."
        }
    }
}

struct AssistantMessage: Codable, Identifiable, Sendable {
    let id: String
    let role: String
    var parts: [[String: AnyJSON]]

    init(role: String, parts: [[String: AnyJSON]] = []) {
        id = UUID().uuidString
        self.role = role
        self.parts = parts
    }
}

enum AssistantTool: String {
    case plan = "einplanen", batch = "mehrere_einplanen", attendance = "anwesenheit_setzen"
    case note = "notiz_hinzufuegen", recipe = "rezept_entwurf_oeffnen", book = "buch_hinzufuegen"
    case remove = "gerichte_entfernen", change = "plan_aendern"

    var title: String {
        switch self {
        case .plan, .batch: "Einplanen"
        case .attendance: "Anwesenheit ändern"
        case .note: "Rezeptnotiz hinzufügen"
        case .recipe: "Rezeptentwurf öffnen"
        case .book: "Kochbuch ins Regal stellen"
        case .remove: "Gerichte entfernen"
        case .change: "Wochenplan ändern"
        }
    }

    init?(part: [String: AnyJSON]) {
        guard let type = part["type"]?.stringValue, type.hasPrefix("tool-") else { return nil }
        self.init(rawValue: String(type.dropFirst(5)))
    }
}

@MainActor
@Observable
final class AssistantStore {
    typealias EventHandler = @MainActor ([String: AnyJSON]) -> Void
    typealias StreamResponse = @MainActor ([AssistantMessage], Recipe?, EventHandler) async throws -> Void
    static let maximumPhotoCount = 5
    static let maximumPhotoBytes = 400_000

    private(set) var messages: [AssistantMessage] = []
    private(set) var busy = false
    private(set) var applying = false
    private(set) var status: AssistantStatus?
    var pendingMealQuestion: MealSlot?
    var error: String?
    var showsComposer: Bool { busy || !hasPending }
    var canAskAboutMeal: Bool { !busy && !applying && !hasPending && status?.enabled != false }
    @ObservationIgnored private let streamResponse: StreamResponse
    @ObservationIgnored private var responseTask: Task<Void, Never>?
    @ObservationIgnored private var statusRequest = UUID()
    @ObservationIgnored private var previews: [String: AssistantPreview] = [:]
    @ObservationIgnored private var lastMealRequest: (slot: MealSlot, recipes: [Recipe])?

    init(streamResponse: @escaping StreamResponse = AssistantTransport.stream) {
        self.streamResponse = streamResponse
    }

    private var hasPending: Bool {
        messages.last?.parts.contains {
            AssistantTool(part: $0) != nil && $0["state"]?.stringValue == "input-available"
        } ?? false
    }

    static func mealQuestionLabel(_ slot: MealSlot) -> String {
        let meal = slot.meal.fullLabel
        var format = Date.FormatStyle().day().month(.wide).year().locale(Locale(identifier: "de_DE"))
        format.timeZone = BerlinDay.calendar.timeZone
        let day = BerlinDay.date(for: slot.date)?.formatted(format) ?? slot.date
        return "\(meal) am \(day)"
    }

    func askAboutMeal(_ slot: MealSlot, demo: Bool, recipes: [Recipe] = []) async {
        guard canAskAboutMeal else {
            pendingMealQuestion = slot
            return
        }
        pendingMealQuestion = nil
        let text = "Schlag ein passendes Gericht vor und plane es ein. Mahlzeit: \(Self.mealQuestionLabel(slot))."
        await send(text, photos: [], recipe: nil, demo: demo, meal: slot, suggestions: Array(recipes.prefix(36)))
    }

    func send(_ input: String, photo: Data?, recipe: Recipe?, demo: Bool, meal: MealSlot? = nil) async {
        await send(input, photos: photo.map { [$0] } ?? [], recipe: recipe, demo: demo, meal: meal)
    }

    func send(_ input: String, photos: [Data], recipe: Recipe?, demo: Bool, meal: MealSlot? = nil,
              suggestions: [Recipe] = []) async {
        guard !busy, !applying, !hasPending else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !photos.isEmpty else { return }
        guard photos.count <= Self.maximumPhotoCount, photos.allSatisfy({ $0.count <= Self.maximumPhotoBytes }) else {
            error = "Hänge bis zu fünf Fotos in einer kleineren Größe an."
            return
        }
        let question = photos.count == 1 ? "Was siehst du auf dem Foto?" : "Was siehst du auf den Fotos?"
        var parts: [[String: AnyJSON]] = [["type": .string("text"), "text": .string(text.isEmpty ? question : text)]]
        parts += photos.map { photo in
            ["type": .string("file"), "mediaType": .string("image/jpeg"),
             "url": .string("data:image/jpeg;base64," + photo.base64EncodedString())]
        }
        lastMealRequest = meal.map { ($0, suggestions) }
        messages.append(AssistantMessage(role: "user", parts: parts))
        await reply(recipe: recipe, demo: demo, meal: meal, suggestions: suggestions)
    }

    func retry(recipe: Recipe?, demo: Bool) async {
        guard !busy, !applying, !hasPending, !messages.isEmpty else { return }
        await reply(recipe: recipe, demo: demo, meal: lastMealRequest?.slot, suggestions: lastMealRequest?.recipes ?? [])
    }

    func clear() {
        guard !busy && !applying else { return }
        messages = []
        previews.removeAll()
        lastMealRequest = nil
        error = nil
    }

    func stop() {
        responseTask?.cancel()
    }

    func refreshStatus(demo: Bool) async throws {
        let request = UUID()
        statusRequest = request
        let current = demo ? AssistantStatus.demo : try await AssistantTransport.fetchStatus()
        if request == statusRequest, !Task.isCancelled { status = current }
    }

    private func reply(recipe: Recipe?, demo: Bool, meal: MealSlot? = nil, suggestions: [Recipe] = []) async {
        guard responseTask == nil else { return }
        busy = true
        error = nil
        defer {
            responseTask = nil
            busy = false
        }
        let task = Task { await receiveReply(recipe: recipe, demo: demo, meal: meal, suggestions: suggestions) }
        responseTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func receiveReply(recipe: Recipe?, demo: Bool, meal: MealSlot?, suggestions: [Recipe]) async {
        let index = messages.count
        let history = Array(messages.suffix(24))
        messages.append(AssistantMessage(role: "assistant"))
        var textParts: [String: Int] = [:]
        var toolParts: [String: Int] = [:]
        do {
            try Task.checkCancellation()
            if demo {
                if let config = DemoAI.configuration {
                    let choices = suggestions.isEmpty ? ["gnocchi": "Tomaten-Gnocchi mit Burrata"] :
                        Dictionary(suggestions.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
                    let response = try await demoReply(config, history: history, recipe: recipe, meal: meal, choices: choices)
                    try Task.checkCancellation()
                    messages[index].parts.append(["type": .string("text"), "text": .string(response.text)])
                    if let draft = response.recipe {
                        let input: JSONObject = ["rezept": .object(draft)]
                        _ = try AssistantActions.recipeDraft(input)
                        consume(demoTool(.recipe, input: input), index: index, textParts: &textParts, toolParts: &toolParts)
                    } else if let meal, let id = response.mealRecipeID, choices[id] != nil {
                        let input: JSONObject = ["datum": .string(meal.date), "mahlzeit": .string(meal.meal.rawValue),
                                                 "rezept_id": .string(id)]
                        consume(demoTool(.plan, input: input), index: index, textParts: &textParts, toolParts: &toolParts)
                    }
                    return
                }
                let slot = meal ?? MealSlot(date: BerlinDay.today(), meal: .lunch)
                messages[index].parts.append(["type": .string("text"), "text": .string("Wie wäre es mit Tomaten-Gnocchi mit Burrata?")])
                consume(["type": .string("tool-input-available"), "toolName": .string("einplanen"),
                         "toolCallId": .string(UUID().uuidString), "input": .object([
                            "datum": .string(slot.date), "mahlzeit": .string(slot.meal.rawValue),
                            "rezept_id": .string("gnocchi"), "rezept_titel": .string("Tomaten-Gnocchi mit Burrata"),
                            "begruendung": .string("Steht in eurer Rezeptsammlung.")
                         ])], index: index, textParts: &textParts, toolParts: &toolParts)
                return
            }
            try await streamResponse(history, recipe) { event in
                guard !Task.isCancelled else { return }
                consume(event, index: index, textParts: &textParts, toolParts: &toolParts)
            }
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled {
                messages[index].parts.removeAll { $0["type"]?.stringValue != "text" || $0["text"]?.stringValue?.isEmpty != false }
                if messages[index].parts.isEmpty { messages.remove(at: index) }
            } else {
                messages.remove(at: index)
                self.error = (error as? AssistantFailure)?.errorDescription ?? "Die Antwort konnte nicht geladen werden."
            }
        }
    }

    private struct DemoReply: Decodable {
        let text: String
        let recipe: JSONObject?
        let mealRecipeID: String?
    }

    private func demoReply(_ config: DemoAI.Configuration, history: [AssistantMessage], recipe: Recipe?, meal: MealSlot?,
                           choices: [String: String]) async throws -> DemoReply {
        let conversation = history.map { message in
            let text = message.parts.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
            return "\(message.role): \(text)"
        }.joined(separator: "\n\n")
        let photos = history.filter { $0.role == "user" }.flatMap { message in
            message.parts.compactMap { part -> String? in
                guard part["type"]?.stringValue == "file", let url = part["url"]?.stringValue,
                      url.hasPrefix("data:image/jpeg;base64,") else { return nil }
                return String(url.dropFirst("data:image/jpeg;base64,".count))
            }
        }
        let context = recipe.map {
            "\($0.title)\nZutaten: \($0.ingredients.map(\.name).joined(separator: ", "))\n\($0.steps.joined(separator: "\n"))"
        } ?? ""
        let planning: String
        if let meal {
            let data = try JSONEncoder().encode(choices)
            planning = "Wähle für \(Self.mealQuestionLabel(meal)) ein Gericht aus diesem Verzeichnis (ID zu Titel): \(String(decoding: data, as: UTF8.self)). Setze mealRecipeID auf die exakte ID des Vorschlags und recipe auf null."
        } else {
            planning = "Setze mealRecipeID auf null."
        }
        let text = try await DemoAI.generate(config, prompt: """
        Du bist Gnocchi, ein deutschsprachiger Rezept- und Küchenassistent. Antworte als JSON-Objekt mit text (String),
        mealRecipeID (String oder null) und recipe (null, außer ein neues Rezept ist ausdrücklich gefragt).
        Für einen Rezeptentwurf ist recipe ein Objekt mit title, servings (Ganzzahl), time_min (Ganzzahl),
        ingredients (Liste mit name und amount als Text), steps (Liste mit Texten) und optional tip.
        \(planning)
        Rezeptkontext: \(context)
        Gespräch:
        \(conversation.suffix(24_000))
        """, images: Array(photos.suffix(Self.maximumPhotoCount)), json: true)
        let reply = try JSONDecoder().decode(DemoReply.self, from: DemoAI.jsonData(text))
        guard !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AssistantFailure.message("Der KI-Anbieter hat keine Antwort geliefert.")
        }
        return reply
    }

    private func demoTool(_ tool: AssistantTool, input: JSONObject) -> JSONObject {
        ["type": .string("tool-input-available"), "toolName": .string(tool.rawValue),
         "toolCallId": .string(UUID().uuidString), "input": .object(input)]
    }

    private func consume(_ event: [String: AnyJSON], index: Int, textParts: inout [String: Int],
                         toolParts: inout [String: Int]) {
        let kind = event["type"]?.stringValue
        switch kind {
        case "text-delta":
            guard let id = event["id"]?.stringValue, let delta = event["delta"]?.stringValue else { return }
            let part = textParts[id] ?? messages[index].parts.count
            if textParts[id] == nil {
                textParts[id] = part
                messages[index].parts.append(["type": .string("text"), "text": .string("")])
            }
            let previous = messages[index].parts[part]["text"]?.stringValue ?? ""
            messages[index].parts[part]["text"] = .string(previous + delta)
        case "tool-input-available":
            guard let id = event["toolCallId"]?.stringValue, let name = event["toolName"]?.stringValue,
                  toolParts[id] == nil else { return }
            toolParts[id] = messages[index].parts.count
            messages[index].parts.append(["type": .string("tool-" + name), "toolCallId": .string(id),
                                           "state": .string("input-available"), "input": event["input"] ?? .null])
        case "tool-output-available", "tool-output-error":
            guard event["preliminary"] != .bool(true), let id = event["toolCallId"]?.stringValue,
                  let part = toolParts[id] else { return }
            messages[index].parts[part]["state"] = .string(kind == "tool-output-error" ? "output-error" : "output-available")
            messages[index].parts[part]["output"] = event["output"]
            messages[index].parts[part]["errorText"] = event["errorText"]
        default: break
        }
    }

    func preview(id: String, household: HouseholdStore) async throws -> AssistantPreview {
        if let preview = previews[id] { return preview }
        guard let part = messages.last?.parts.first(where: {
            $0["toolCallId"]?.stringValue == id && $0["state"]?.stringValue == "input-available"
        }), let tool = AssistantTool(part: part) else {
            throw AssistantFailure.message("Der Vorschlag ist nicht mehr verfügbar.")
        }
        let loaded = try await AssistantActions.preview(tool, input: part["input"]?.objectValue ?? [:], household: household)
        try Task.checkCancellation()
        if let preview = previews[id] { return preview }
        previews[id] = loaded
        return loaded
    }

    func respond(id: String, approve: Bool, household: HouseholdStore, recipe: Recipe?,
                 selectedInput: JSONObject? = nil,
                 openDraft: (RecipeDraft) -> Void) async {
        guard !busy, !applying, let index = messages.indices.last,
              let position = messages[index].parts.firstIndex(where: { $0["toolCallId"]?.stringValue == id }),
              messages[index].parts[position]["state"]?.stringValue == "input-available",
              let tool = AssistantTool(part: messages[index].parts[position]) else { return }
        applying = true
        let original = messages[index].parts[position]["input"]?.objectValue ?? [:]
        let input = selectedInput ?? original
        var success = false
        var result = "Nicht übernommen."
        if approve {
            do {
                guard let expectedPreview = previews[id] else {
                    throw AssistantFailure.message("Die Vorschau des Vorschlags fehlt.")
                }
                if tool != .plan, tool != .batch {
                    let current = try await AssistantActions.preview(tool, input: original, household: household)
                    guard current.lines == expectedPreview.lines else { throw AssistantFailure.planChanged }
                    if tool == .change {
                        guard let approved = expectedPreview.planChange, let updated = current.planChange,
                              approved.matches(updated) else { throw AssistantFailure.planChanged }
                    }
                }
                if tool == .recipe {
                    var draft = try AssistantActions.recipeDraft(input)
                    let config = household.isDemo ? DemoAI.configuration : nil
                    if !household.isDemo || config != nil, let review = try? await RecipeAIService.review(
                        title: draft.title, ingredients: draft.ingredients.map(\.name),
                        steps: draft.steps.components(separatedBy: "\n\n"), demo: config
                    ) {
                        draft.applyIngredientReview(review)
                    }
                    openDraft(draft)
                    result = "Rezeptentwurf im Formular geöffnet."
                } else {
                    result = try await AssistantActions.apply(tool, input: input, household: household, confirmed: expectedPreview)
                }
                success = true
            } catch {
                result = (error as? AssistantFailure)?.errorDescription ?? "Die Änderung konnte nicht übernommen werden."
            }
        }
        messages[index].parts[position]["state"] = .string("output-available")
        messages[index].parts[position]["output"] = .object(["ok": .bool(success), "meldung": .string(result)])
        previews[id] = nil
        applying = false
        if !hasPending && !household.isDemo { await reply(recipe: recipe, demo: false) }
    }
}

enum AssistantTransport {
    private struct Body: Encodable {
        let messages: [AssistantMessage]
        let kontext: [String: String]?
    }

    private static let maximumBodyBytes = 4_400_000
    private static let imageHistoryBudget = 3_500_000

    private static func body(messages: [AssistantMessage], recipe: Recipe?) throws -> Data {
        var history = messages
        var imageBytes = 0
        for index in history.indices.reversed() {
            guard history[index].role == "user" else { continue }
            let photoBytes = history[index].parts.reduce(0) { bytes, part in
                bytes + (part["type"]?.stringValue == "file" ? part["url"]?.stringValue?.utf8.count ?? 0 : 0)
            }
            // Bei langen Chats bleiben Text und die neuesten Fotos erhalten.
            if imageBytes > 0, imageBytes + photoBytes > imageHistoryBudget {
                history[index].parts.removeAll { $0["type"]?.stringValue == "file" }
            } else {
                imageBytes += photoBytes
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try encoder.encode(Body(
            messages: history, kontext: recipe.map { ["rezept_id": $0.id, "rezept_titel": $0.title] }
        ))
        guard data.count <= maximumBodyBytes else {
            throw AssistantFailure.message("Der Chat ist für den Versand zu groß. Starte einen neuen Chat und hänge deine Fotos dort an.")
        }
        return data
    }

    @MainActor
    static func stream(messages: [AssistantMessage], recipe: Recipe?, receive: AssistantStore.EventHandler) async throws {
        var request = try await authorizedRequest(path: "api/ai/chat", timeout: 75)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try body(messages: messages, recipe: recipe)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await withTaskCancellationHandler {
            try await consumeStream(bytes, response: response, receive: receive)
        } onCancel: {
            bytes.task.cancel()
        }
    }

    @MainActor
    private static func consumeStream(_ bytes: URLSession.AsyncBytes, response: URLResponse,
                                      receive: AssistantStore.EventHandler) async throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 413 {
            throw AssistantFailure.message("Der Chat ist für den Versand zu groß. Starte einen neuen Chat und hänge deine Fotos dort an.")
        }
        if !(200..<300).contains(http.statusCode) {
            var body = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                body.append(byte)
                if body.count >= 64_000 { break }
            }
            let details = try? JSONDecoder().decode([String: String].self, from: body)
            throw AssistantFailure.message(details?["error"] ?? "Der Assistent ist gerade nicht verfügbar.")
        }
        var ended = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { ended = true; break }
            guard let event = try? JSONDecoder().decode([String: AnyJSON].self, from: Data(payload.utf8)) else { continue }
            switch event["type"]?.stringValue {
            case "finish": ended = true
            case "error", "abort":
                throw AssistantFailure.message(event["errorText"]?.stringValue ?? "Die Antwort wurde unterbrochen.")
            default: receive(event)
            }
        }
        guard ended else { throw AssistantFailure.message("Die Antwort wurde unterbrochen.") }
    }

    static func authorizedRequest(path: String, timeout: TimeInterval) async throws -> URLRequest {
        let token = try await Backend.client.auth.session.accessToken
        var request = URLRequest(url: Backend.site.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}
