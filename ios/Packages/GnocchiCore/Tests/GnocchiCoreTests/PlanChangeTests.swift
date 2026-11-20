import Foundation
import Testing
@testable import GnocchiCore

struct PlanChangeTests {
    @Test("Beim Tausch wandern Reste und Käufe wie in lib/plan-change.ts")
    func moveKeepsCookAndMovesPurchases() throws {
        let from = MealSlot(date: "2026-11-14", meal: .lunch)
        let to = MealSlot(date: "2026-11-15", meal: .dinner)
        let plan = [
            MealPlanEntry(id: "a", date: from.date, meal: from.meal, recipeID: "gn", cookID: "lin", servingsOverride: 5),
            MealPlanEntry(id: "b", date: to.date, meal: to.meal, recipeID: "fish", cookID: "meli"),
            MealPlanEntry(id: "rest", date: "2026-11-16", meal: .dinner, leftoverOf: "a")
        ]
        let purchases = [Purchase(id: "buy", dishID: "a", key: "gnocchi|g", name: "Gnocchi",
                                  amount: 500, unit: "g", boughtAt: .now, boughtBy: "lin")]
        let result = try #require(PlanChange.move(from, to).applying(to: plan, purchases: purchases, today: from.date))
        #expect(result.plan.map(\.id) == ["rest", "a", "b"])
        #expect(result.plan.map(\.recipeID) == [nil, "fish", "gn"])
        #expect(result.plan.map(\.cookID) == [nil, "lin", "meli"])
        #expect(result.plan.allSatisfy { $0.servingsOverride == nil })
        #expect(result.plan.first?.leftoverOf == "b")
        #expect(result.purchases.first?.dishID == "b")
        #expect(result.purchases.first?.boughtBy == "lin")
    }
    @Test("Reste folgen dem Kochtag über die Wochengrenze und behalten eigene Gäste")
    func moveValidatesLeftoverTimeline() throws {
        let origin = MealPlanEntry(id: "origin", date: "2026-11-20", meal: .lunch, recipeID: "gn")
        let child = MealPlanEntry(id: "leftovers", date: "2026-11-25", meal: .dinner, leftoverOf: origin.id, familyGuests: 2)
        let valid = MealSlot(date: "2026-11-23", meal: .lunch)
        let afterChild = MealSlot(date: "2026-11-26", meal: .lunch)
        let past = MealSlot(date: "2026-11-17", meal: .lunch)
        let tooLate = MealSlot(date: "2026-12-01", meal: .lunch)
        let plan = [origin, child]
        let today = "2026-11-18"

        let moved = try #require(PlanChange.move(origin.slot, valid).applying(to: plan, purchases: [], today: today))
        let destination = try #require(moved.plan.first { $0.slot == valid })
        #expect(moved.plan.first { $0.id == child.id }?.leftoverOf == destination.id)
        #expect(moved.plan.first { $0.id == child.id }?.familyGuests == 2)
        #expect(PlanChange.move(origin.slot, afterChild).applying(to: plan, purchases: [], today: today) == nil)
        #expect(PlanChange.move(origin.slot, past).applying(to: plan, purchases: [], today: today) == nil)
        #expect(PlanChange.move(child.slot, tooLate).applying(to: plan, purchases: [], today: today) == nil)
        #expect(PlanChange.move(child.slot, origin.slot).applying(to: plan, purchases: [], today: today) == nil)
    }

    @Test("Der Restezeitraum bezieht sich auf das Zieldatum und schließt den zehnten Tag ein")
    func mealPrepTimeWindow() {
        let target = MealSlot(date: "2026-12-05", meal: .dinner)
        let tenDays = MealPlanEntry(id: "a", date: "2026-11-25", meal: .dinner, recipeID: "gn")
        let elevenDays = MealPlanEntry(id: "b", date: "2026-11-24", meal: .dinner, recipeID: "gn")
        let sameDay = MealPlanEntry(id: "c", date: target.date, meal: .lunch, recipeID: "gn")
        let leftover = MealPlanEntry(id: "d", date: "2026-11-30", meal: .dinner, leftoverOf: "a")
        #expect(tenDays.canBeLeftoverSource(for: target))
        #expect(!elevenDays.canBeLeftoverSource(for: target))
        #expect(sameDay.canBeLeftoverSource(for: target))
        #expect(!leftover.canBeLeftoverSource(for: target))
    }

}
