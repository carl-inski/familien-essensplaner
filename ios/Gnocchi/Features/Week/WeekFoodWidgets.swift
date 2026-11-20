import GnocchiCore
import SwiftUI

struct WeekFoodWidgets: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showingNutrients = false
    let start: String
    let plannedDays: Int
    let plannedMeals: Int

    private var figures: Figures {
        let end = BerlinDay.adding(6, to: start)
        let plan = store.planIncludingLaterLeftovers
        let leftovers = Dictionary(grouping: plan.filter { $0.leftoverOf != nil && $0.status != .cancelled },
                                   by: { $0.leftoverOf ?? "" })
        var totals = Figures()
        for entry in store.plan where entry.date >= start && entry.date <= end && entry.status != .cancelled {
            guard entry.recipeID != nil || entry.leftoverOf != nil else { continue }
            let recipe = store.recipeForMeal(recipeID: entry.recipeID, leftoverOf: entry.leftoverOf)
            let eaters = Planning.eaters(at: entry.slot, members: store.members, attendance: store.attendance, familyGuests: entry.familyGuests)
            let batch = leftovers[entry.id] ?? []
            let portions = entry.leftoverOf != nil || batch.isEmpty ? entry.servingsOverride ?? eaters : eaters
            if portions > 0 {
                totals.meals += 1
                if let recipe {
                    var hasValues = false
                    for nutrient in RecipeNutrient.allCases {
                        guard let amount = nutrient.amount(in: recipe) else { continue }
                        totals.nutrients[nutrient, default: NutrientTotal()].amount += amount * Double(portions)
                        totals.nutrients[nutrient, default: NutrientTotal()].mealCount += 1
                        hasValues = true
                    }
                    if hasValues { totals.withNutrition += 1 }
                }
            }
            if entry.leftoverOf == nil {
                let cookPortions = Planning.servings(for: entry, in: plan, members: store.members, attendance: store.attendance)
                guard cookPortions > 0 else { continue }
                totals.cookingDays += 1
                if let cents = recipe?.pricePerServingCents {
                    totals.cost += FoodMoney.amount(cents) * Decimal(cookPortions)
                    totals.withPrice += 1
                }
            }
        }
        return totals
    }

    var body: some View {
        let figures = figures
        let budget = store.weeklyBudgetCents
        let costProgress = budget.map { NSDecimalNumber(decimal: figures.cost / FoodMoney.amount($0)).doubleValue } ?? 0
        let nutrientsProgress = Double(figures.withNutrition) / Double(max(1, figures.meals))
        let cards = HStack(alignment: .top, spacing: 8) {
            tile("Wochenplan", symbol: "fork.knife", progress: Double(plannedDays) / 7, tint: Theme.ink,
                 value: "\(plannedDays) von 7", detail: "\(plannedMeals) Mahlzeiten")
            tile("Kosten", symbol: "eurosign", progress: figures.withPrice == 0 ? 0 : costProgress,
                 tint: costProgress > 1 ? .red : Color(light: 0xC65D38, dark: 0xFF9A78),
                 value: figures.withPrice == 0 ? "Keine Preise" : figures.cost.formatted(.currency(code: "EUR")),
                 detail: costDetail(figures, budget: budget))
            Button { showingNutrients = true } label: {
                tile("Nährwerte", symbol: "flame.fill", progress: nutrientsProgress, tint: Theme.success,
                     value: figures.nutrients[.energy].map { amountLabel($0.amount, nutrient: .energy) } ?? "Übersicht",
                     detail: "\(figures.withNutrition) von \(figures.meals) erfasst")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Nährwerte im Wochenplan öffnen")
        }
        Group {
            if textSize.isAccessibilitySize {
                ScrollView(.horizontal) { cards.fixedSize(horizontal: true, vertical: false) }
            } else {
                cards
            }
        }
        .sheet(isPresented: $showingNutrients) {
            NavigationStack {
                List {
                    Section {
                        ForEach(RecipeNutrient.allCases) { nutrient in
                            let total = figures.nutrients[nutrient]
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent(nutrient.label,
                                               value: total.map { amountLabel($0.amount, nutrient: nutrient) } ?? "Keine Angaben")
                                if let total, total.mealCount < figures.meals {
                                    Text("\(total.mealCount) von \(figures.meals) Mahlzeiten")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text("Summe für die eingeplanten Portionen der Familie in dieser Woche.")
                    }
                }
                .navigationTitle("Nährwerte der Woche")
                .gnScreen()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { showingNutrients = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .task(id: scenePhase) {
            if scenePhase == .active, let family = store.household {
                _ = try? await store.loadWeeklyBudget(for: family)
            }
        }
    }

    private func amountLabel(_ value: Double, nutrient: RecipeNutrient) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) \(nutrient.unit)"
    }

    private func costDetail(_ figures: Figures, budget: Int?) -> String {
        let target = budget.map { "Budget \(FoodMoney.amount($0).formatted(.currency(code: "EUR").precision(.fractionLength(0...2))))" }
            ?? "Ohne Budget"
        if figures.withPrice < figures.cookingDays {
            return target + "\n\(figures.withPrice) von \(figures.cookingDays) mit Preis"
        }
        return target
    }

    private func tile(_ label: String, symbol: String, progress: Double, tint: Color,
                      value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            Text(value).font(.headline.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.68)
            Text(detail).font(.caption2).foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 35, alignment: .topLeading)
            ring(symbol: symbol, progress: progress, tint: tint, size: 48)
                .frame(maxWidth: .infinity)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .gnCard(padding: 9, radius: 19)
        .accessibilityElement(children: .combine)
    }

    private func ring(symbol: String, progress: Double, tint: Color, size: CGFloat) -> some View {
        ProgressRing(value: progress, lineWidth: size > 60 ? 8 : 6, tint: tint) {
            Image(systemName: symbol).font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .padding(4)
        .accessibilityHidden(true)
    }

    private struct NutrientTotal {
        var amount = 0.0
        var mealCount = 0
    }

    private struct Figures {
        var cost: Decimal = 0
        var nutrients: [RecipeNutrient: NutrientTotal] = [:]
        var cookingDays = 0
        var withPrice = 0
        var meals = 0
        var withNutrition = 0
    }
}
