import GnocchiCore
import Testing

@Test("Vorschlag folgt der Web-Gewichtung auch bei aufeinanderfolgenden Fleischgerichten")
func suggestionMatchesWeb() {
    func candidate(_ id: String, book: String? = nil, tags: [String] = []) -> MealSuggestion.Candidate {
        .init(id: id, cookbookID: book, tags: tags, categories: [])
    }
    let recipes = [
        candidate("recent"), candidate("edge"), candidate("book", book: "buch"),
        candidate("meat"), candidate("snack", tags: ["Snack"]), candidate("existing")
    ]
    let plan: [MealSuggestion.Planned] = [
        .init(slot: .init(date: "2026-10-26", meal: .lunch), recipeID: "previous"),
        .init(slot: .init(date: "2026-10-27", meal: .dinner), recipeID: "existing")
    ]
    let slot = MealSlot(date: "2026-10-26", meal: .dinner)
    let history = ["recent": "2026-10-10", "edge": "2026-10-09"]
    // Output of pickSuggestion in lib/suggest.ts for the same inputs.
    for (random, expected) in [(0.0, "edge"), (0.04, "edge"), (0.08, "book"), (0.5, "book"), (0.999, "meat")] {
        #expect(MealSuggestion.pick(from: recipes, lastCooked: history, plan: plan, slot: slot,
                                    today: "2026-10-23", avoiding: [], random: random)?.id == expected)
    }
}

@Test("Vorschläge berücksichtigen Frühstücks- und Snack-Kategorien")
func optionalMealSuggestions() {
    let recipes = [
        MealSuggestion.Candidate(id: "dinner", cookbookID: nil, tags: [], categories: ["Pasta"]),
        MealSuggestion.Candidate(id: "breakfast", cookbookID: nil, tags: ["Frühstück"], categories: []),
        MealSuggestion.Candidate(id: "snack", cookbookID: nil, tags: [], categories: ["Snack"]),
    ]
    let day = "2026-11-16"
    let expectations: [(Meal, String)] = [(.breakfast, "breakfast"), (.snack, "snack")]
    for (meal, expected) in expectations {
        let slot = MealSlot(date: day, meal: meal)
        #expect(MealSuggestion.pick(from: recipes, lastCooked: [:], plan: [], slot: slot,
                                    today: day, avoiding: [], random: 0)?.id == expected)
    }
}
