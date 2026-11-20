import Foundation
import Testing
@testable import GnocchiCore

// Erwartete Ergebnisse aus lib/dates.ts und lib/planning.ts (tsx).
struct PlanningTests {
    @Test func berlinCalendarAcrossSpringClockChange() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-03-28T23:30:00Z"))
        #expect(BerlinDay.today(now: instant) == "2026-03-29")
        #expect(BerlinDay.days(from: "2026-03-29", count: 3) == [
            "2026-03-29", "2026-03-30", "2026-03-31"
        ])
    }

    @Test func configuredMealsKeepOnlySavedPlansAndAttendanceInOrder() {
        let date = "2026-11-16"
        let plan = [
            MealPlanEntry(id: "empty", date: date, meal: .dinner),
            MealPlanEntry(id: "note", date: date, meal: .snack, note: "Nach der Schule"),
            MealPlanEntry(id: "cancelled", date: date, meal: .lunch, status: .cancelled),
            MealPlanEntry(id: "later", date: "2026-11-17", meal: .dinner, recipeID: "recipe"),
        ]
        let attendance = [
            Attendance(id: "a", memberID: "member", date: date, meal: .breakfast, status: .away, guests: 0)
        ]

        #expect(Planning.configuredMeals(on: date, plan: plan, attendance: attendance) == [.breakfast, .lunch, .snack])
        #expect(Meal.allCases.map(\.displayOrder) == [0, 1, 2, 3])
    }

    @Test func attendanceOverridesAndLeftoverServings() {
        let members = [
            Member(id: "a", name: "A", defaultWeek: ["sun": [.dinner: .away]]),
            Member(id: "b", name: "B")
        ]
        let dinner = MealSlot(date: "2026-03-29", meal: .dinner)
        let nextLunch = MealSlot(date: "2026-03-30", meal: .lunch)
        let attendance = [
            Attendance(id: "1", memberID: "a", date: dinner.date, meal: dinner.meal, status: .present, guests: 2),
            Attendance(id: "2", memberID: "b", date: dinner.date, meal: dinner.meal, status: .away, guests: 5)
        ]
        let main = MealPlanEntry(id: "p1", date: dinner.date, meal: dinner.meal)
        let leftovers = MealPlanEntry(id: "p2", date: nextLunch.date, meal: nextLunch.meal, leftoverOf: main.id)
        #expect(Planning.effectiveStatus(for: members[0], at: dinner, attendance: []).status == .away)
        #expect(Planning.eaters(at: dinner, members: members, attendance: attendance) == 3)
        #expect(Planning.servings(for: main, in: [main, leftovers], members: members, attendance: attendance) == 5)
    }
}
