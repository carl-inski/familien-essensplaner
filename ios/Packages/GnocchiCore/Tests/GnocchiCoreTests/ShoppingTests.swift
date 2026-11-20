import Foundation
import Testing
@testable import GnocchiCore

struct ShoppingTests {
    @Test("Bring! bekommt bei geänderten Mengen denselben neuen Cache-Stand wie im Web")
    func exportVersionMatchesWeb() {
        #expect(Shopping.exportVersion(["Öl & Salz", "700 g Gnocchi", "🍋 Zitrone"]) == "7e1rs7")
        #expect(Shopping.exportVersion(["Öl & Salz", "350 g Gnocchi", "🍋 Zitrone"]) == "tdl9vq")
    }

    @Test("Die Einkaufsliste unterscheidet abgehakten Vorrat, Einkäufe und angerechnete Restmengen")
    func purchaseOrigins() throws {
        let day = "2026-11-11"
        let now = Date.now
        let dish = MealPlanEntry(id: "dish", date: day, meal: .lunch, recipeID: "gn", servingsOverride: 1)
        let ingredients = [
            ShoppingIngredient(name: "Tomaten", quantity: Quantity(amount: 400, unit: "g")),
            ShoppingIngredient(name: "Gnocchi", quantity: Quantity(amount: 250, unit: "g")),
            ShoppingIngredient(name: "Basilikum", quantity: nil)
        ]
        let recipes = ["gn": ShoppingRecipe(title: "Gnocchi", servings: 1, ingredients: ingredients)]
        let tomatoKey = try #require(Shopping.stockEntry("150 g Tomaten")?.key)
        let purchases = [
            Purchase(id: "stock", dishID: nil, key: tomatoKey, name: "Tomaten", amount: 150, unit: "g",
                     boughtAt: now, isStock: true, boughtBy: "a"),
            Purchase(id: "pasta", dishID: dish.id, key: "gnocchi|g", name: "Gnocchi", amount: 250, unit: "g",
                     boughtAt: now, boughtBy: "a"),
            Purchase(id: "herbs", dishID: dish.id, key: "basilikum|", name: "Basilikum", amount: nil, unit: nil,
                     boughtAt: now, isStock: true, boughtBy: "b")
        ]

        let result = Shopping.calculate(plan: [dish], recipes: recipes, members: [], attendance: [],
                                        pantry: [], purchases: purchases, today: day, now: now)
        #expect(result.open.map(\.text) == ["250 g Tomaten"])
        #expect(result.open.first?.usesStock == true)
        #expect(result.bought.first { $0.name == "Gnocchi" }?.fromStock == false)
        #expect(result.bought.first { $0.name == "Gnocchi" }?.boughtBy == "a")
        #expect(result.bought.first { $0.name == "Basilikum" }?.fromStock == true)
        #expect(result.bought.first { $0.name == "Basilikum" }?.boughtBy == "b")
    }

    @Test("Mengen, Nachkauf und Vorrat entsprechen tests/purchases.test.ts")
    func shoppingWithSharedPurchases() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-11T17:30:00Z"))
        let members = ["a", "b", "c"].map { Member(id: $0, name: $0) }
        let dish = MealPlanEntry(id: "fr", date: "2026-11-13", meal: .dinner, recipeID: "gn")
        let ingredients = [
            ShoppingIngredient(name: "Gnocchi", quantity: Quantity(amount: 600, unit: "g")),
            ShoppingIngredient(name: "Tomaten", quantity: Quantity(amount: 400, unit: "g")),
            ShoppingIngredient(name: "Basilikum", quantity: nil)
        ]
        let recipes = ["gn": ShoppingRecipe(title: "Tomaten-Gnocchi", servings: 4, ingredients: ingredients)]
        let first = Shopping.calculate(plan: [dish], recipes: recipes, members: members, attendance: [],
                                       pantry: [], purchases: [], today: "2026-11-11", now: now)
        #expect(first.open.map(\.text).sorted() == ["300 g Tomaten", "450 g Gnocchi", "Basilikum"])
        let bought = first.open.flatMap(\.parts).enumerated().map { index, part in
            Purchase(id: String(index), dishID: part.dishID, key: part.key, name: part.name, amount: part.amount,
                     unit: part.unit, boughtAt: now)
        }
        let next = Shopping.calculate(plan: [dish], recipes: recipes, members: members,
                                      attendance: [Attendance(id: "g", memberID: "a", date: dish.date,
                                                              meal: dish.meal, status: .present, guests: 2)],
                                      pantry: [], purchases: bought, today: "2026-11-11", now: now)
        #expect(next.open.map(\.text).sorted() == ["200 g Tomaten", "300 g Gnocchi"])
        let cancelled = MealPlanEntry(id: dish.id, date: dish.date, meal: dish.meal, recipeID: dish.recipeID, status: .cancelled)
        let stock = Shopping.calculate(plan: [cancelled], recipes: recipes, members: members, attendance: [],
                                       pantry: [], purchases: bought, today: "2026-11-11", now: now)
        #expect(stock.stock.map(\.text).sorted() == ["300 g Tomaten", "450 g Gnocchi", "Basilikum"])
    }
}
@Test("Knuspr-Links behalten Mengen, Umlaute und Pluszeichen")
func knusprHandoffMatchesWeb() throws {
    let prompt = Knuspr.prompt(lines: ["600 g Basmatireis", "Öl + Salz & Pfeffer"])
    #expect(prompt.hasSuffix("\n\n- 600 g Basmatireis\n- Öl + Salz & Pfeffer"))
    for assistant in [Knuspr.Assistant.claude, .chatGPT] {
        let url = try #require(Knuspr.link(for: assistant, prompt: prompt))
        #expect(url.absoluteString.hasSuffix("%C3%96l%20%2B%20Salz%20%26%20Pfeffer"))
        #expect(url.absoluteString.hasPrefix(assistant.rawValue + "?q="))
    }
}
