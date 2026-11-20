import Foundation
import Supabase

struct RecipeIngredientReview {
    let aliases: [String: [String]]
    let missing: [String]

    var metadata: AnyJSON {
        .object(aliases.mapValues { .array($0.map(AnyJSON.string)) })
    }
}

enum RecipeAIService {
    private struct ReviewRequest: Encodable {
        let task = "review"
        let title: String
        let ingredients: [String]
        let steps: [String]
    }

    private struct ReviewResponse: Decodable {
        struct Alias: Decodable { let index: Int; let text: String }
        let aliases: [Alias]
        let missing: [Int]
    }

    private struct PriceRequest: Encodable {
        let task = "price"
        let title: String
        let ingredients: [String]
        let servings: Int
    }

    private struct PriceResponse: Decodable { let cents: Int }
    private struct Failure: Decodable { let error: String }

    static func review(title: String, ingredients: [String], steps: [String],
                       demo: DemoAI.Configuration? = nil) async throws -> RecipeIngredientReview {
        let ingredients = ingredients.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let steps = steps.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !ingredients.isEmpty, !steps.isEmpty else { return RecipeIngredientReview(aliases: [:], missing: []) }
        let request = ReviewRequest(title: title, ingredients: ingredients, steps: steps)
        let response: ReviewResponse = try await post(request, demo: demo, instruction: """
        Ordne Zutaten (Index ab 0) den tatsächlich verwendeten Namen und Kurzformen in den Zubereitungsschritten zu.
        Liefere JSON mit aliases (Liste aus {index, text}) und missing (Liste nicht erwähnter Zutatenindizes).
        Erfinde keine Wörter und gib keine zusammengesetzten Wörter als Treffer aus, wenn sie eine andere Zutat bezeichnen.
        """)
        var aliases: [String: [String]] = [:]
        for item in response.aliases where ingredients.indices.contains(item.index) && (1...90).contains(item.text.count) {
            let key = ingredients[item.index].lowercased()
            if !(aliases[key] ?? []).contains(item.text) { aliases[key, default: []].append(item.text) }
        }
        return RecipeIngredientReview(aliases: aliases, missing: response.missing.compactMap {
            ingredients.indices.contains($0) ? ingredients[$0] : nil
        })
    }

    static func estimatePrice(for recipe: Recipe, demo: DemoAI.Configuration? = nil) async throws -> Int {
        guard let portions = recipe.servings, portions > 0 else {
            throw RecipeImportFailure(message: "Für die Schätzung braucht das Rezept eine Portionszahl.")
        }
        let ingredients = recipe.ingredients.map {
            [$0.amountLabel(factor: 1), $0.name].filter { !$0.isEmpty }.joined(separator: " ")
        }
        let response: PriceResponse = try await post(
            PriceRequest(title: recipe.title, ingredients: ingredients, servings: portions), demo: demo,
            instruction: "Schätze die Zutatenkosten pro Portion für einen Lebensmitteleinkauf in Deutschland. Gib ausschließlich JSON mit cents (Ganzzahl in Eurocent) zurück."
        )
        guard (0...100_000).contains(response.cents) else { throw RecipeImportFailure(message: "Die Schätzung war ungültig.") }
        return response.cents
    }

    private static func post<Response: Decodable>(_ payload: some Encodable, demo: DemoAI.Configuration?, instruction: String) async throws -> Response {
        let body = try JSONEncoder().encode(payload)
        if let demo {
            let input = String(decoding: body, as: UTF8.self)
            let answer = try await DemoAI.generate(demo, prompt: "\(instruction)\nRezeptdaten: \(input)", json: true)
            return try JSONDecoder().decode(Response.self, from: DemoAI.jsonData(answer))
        }
        let token = try await Backend.client.auth.session.accessToken
        var request = URLRequest(url: Backend.site.appending(path: "api/ai/recipe-assist"), timeoutInterval: 33)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status else {
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw RecipeImportFailure(message: failure?.error ?? "Die KI-Funktion ist gerade nicht verfügbar.")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
