import SwiftUI

enum RecipeSection: String, CaseIterable, Codable, Identifiable {
    case ingredients, preparation, tips, rating, nutrition, price, notes, history, about

    var id: Self { self }

    static func ordered(_ saved: String) -> [Self] {
        var seen: Set<Self> = []
        let chosen = saved.split(separator: ",").compactMap { Self(rawValue: String($0)) }
        return (chosen + allCases).filter { seen.insert($0).inserted }
    }
}

struct RecipeSectionDrag: Sendable {
    let section: RecipeSection
    let handle: @MainActor @Sendable (RecipeSection, String, UILongPressGestureRecognizer, UIScrollView) -> Void
}

struct RecipeSectionHandle: UIViewRepresentable {
    let title: String
    let drag: RecipeSectionDrag

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let gesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.track(_:)))
        gesture.minimumPressDuration = 0.18
        gesture.allowableMovement = 15
        view.addGestureRecognizer(gesture)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.handle = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(handle: self) }

    @MainActor final class Coordinator: NSObject {
        var handle: RecipeSectionHandle

        init(handle: RecipeSectionHandle) { self.handle = handle }

        @objc func track(_ gesture: UILongPressGestureRecognizer) {
            var ancestor = gesture.view?.superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    handle.drag.handle(handle.drag.section, handle.title, gesture, scroll)
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

struct RecipeNutritionTile: View {
    let recipe: Recipe

    private var macros: [Macro] {
        [RecipeNutrient.protein, .carbohydrates, .fat].compactMap { nutrient in
            nutrient.amount(in: recipe).map { Macro(nutrient: nutrient, grams: $0) }
        }
    }

    var body: some View {
        RecipePanel("Nährwerte") {
            let values = macros
            if let energy = RecipeNutrient.energy.amount(in: recipe) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(energy, format: .number.precision(.fractionLength(0))).font(Theme.display(33))
                    Text("kcal").foregroundStyle(Theme.recipeSecondary)
                    Spacer()
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.43))
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
            if !values.isEmpty {
                let total = values.map(\.grams).reduce(0, +)
                if total > 0 {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            ForEach(values) { macro in
                                Rectangle().fill(macro.color)
                                    .frame(width: proxy.size.width * CGFloat(macro.grams / total))
                            }
                        }
                        .clipShape(.capsule)
                    }
                    .frame(height: 10)
                    .accessibilityHidden(true)
                }
                ForEach(values) { macro in
                    HStack(spacing: 8) {
                        Circle().fill(macro.color).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(macro.nutrient.label)
                        Spacer(minLength: 6)
                        Text("\(macro.grams.formatted(.number.precision(.fractionLength(0...1)))) g")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
            let additional = recipe.nutrition?.filter { key, _ in
                !RecipeNutrient.allCases.contains {
                    $0.keys.contains(key.lowercased()) && $0.amount(in: recipe) != nil
                } && key != "text"
            } ?? [:]
            ForEach(additional.keys.sorted(), id: \.self) { key in
                LabeledContent(key, value: additional[key] ?? "").font(.subheadline)
            }
            if values.isEmpty, RecipeNutrient.energy.amount(in: recipe) == nil, additional.isEmpty {
                Text(recipe.nutrition?["text"] ?? "Keine Angaben")
                    .foregroundStyle(Theme.recipeSecondary)
            }
            if recipe.nutrition?.isEmpty == false {
                Text(recipe.nutritionEstimated == true ? "Pro Portion · geschätzt" : "Pro Portion")
                    .font(.footnote).foregroundStyle(Theme.recipeSecondary)
            }
        }
    }

    private struct Macro: Identifiable {
        let nutrient: RecipeNutrient
        let grams: Double
        var id: RecipeNutrient { nutrient }
        var color: Color {
            switch nutrient {
            case .protein: Color(red: 1, green: 0.65, blue: 0.57)
            case .carbohydrates: Color(red: 1, green: 0.80, blue: 0.47)
            case .fat: Color(red: 0.63, green: 0.82, blue: 0.99)
            case .energy: .white
            }
        }
    }
}

struct RecipePortionPriceTile: View {
    @Environment(HouseholdStore.self) private var store
    let recipe: Recipe
    let portions: Int?
    @State private var draftCents: Int?
    @State private var estimated = false
    @State private var estimating = false
    @State private var saving = false
    @State private var error: String?
    @State private var estimateCeiling = 2500

    init(recipe: Recipe, portions: Int?) {
        self.recipe = recipe
        self.portions = portions
        _draftCents = State(initialValue: recipe.pricePerServingCents)
        _estimated = State(initialValue: recipe.priceIsEstimate)
    }

    private var pending: Bool {
        draftCents != recipe.pricePerServingCents || (draftCents != nil && estimated != recipe.priceIsEstimate)
    }

    var body: some View {
        RecipePanel("Preis pro Portion") {
            HStack(alignment: .firstTextBaseline) {
                Text(draftCents.map(currency) ?? "—")
                    .font(Theme.display(32, relativeTo: .title)).monospacedDigit()
                Spacer()
                if let cost = draftCents, let portions, portions > 1 {
                    Text("\(currency(cost * portions)) \u{00B7} \(portions) Portionen")
                        .font(.footnote).foregroundStyle(Theme.recipeSecondary)
                }
            }
            if draftCents != nil, estimated {
                Text(store.isDemo && DemoAI.configuration == nil ? "Demo-Schätzung" : "KI-Schätzung für den Lebensmitteleinkauf")
                    .font(.footnote).foregroundStyle(Theme.recipeSecondary)
            }
            Slider(value: Binding(
                get: { Double(draftCents ?? 0) },
                set: { draftCents = Int($0.rounded()); estimated = false; error = nil }
            ), in: 0...Double(max(estimateCeiling, recipe.pricePerServingCents ?? 0)), step: 5)
            .tint(.white)
            .accessibilityLabel("Preis pro Portion")
            .accessibilityValue(draftCents.map(currency) ?? "Kein Preis")
            let controls = HStack {
                Button {
                    Task { await estimate() }
                } label: {
                    Label(estimating ? "Schätzt …" : "KI-Schätzung", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(recipe.ingredients.isEmpty)
                Spacer()
                Button("Sichern") { Task { await save() } }
                    .buttonStyle(.bordered)
                    .disabled(!pending)
            }
            controls
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.recipeSecondary) }
        }
        .disabled(saving || estimating)
        .onChange(of: recipe.pricePerServingCents) { old, new in
            if draftCents == old || draftCents == new {
                draftCents = new
                estimated = recipe.priceIsEstimate
            }
        }
    }

    private func currency(_ cents: Int) -> String {
        FoodMoney.amount(cents).formatted(.currency(code: "EUR"))
    }

    private func estimate() async {
        estimating = true
        error = nil
        defer { estimating = false }
        do {
            let cents: Int
            let config = store.isDemo ? DemoAI.configuration : nil
            if store.isDemo && config == nil {
                cents = recipe.pricePerServingCents ?? 325
            } else {
                cents = try await RecipeAIService.estimatePrice(for: recipe, demo: config)
            }
            draftCents = cents
            estimated = true
            estimateCeiling = max(2500, cents + 500)
        } catch let failure as RecipeImportFailure {
            error = failure.message
        } catch {
            self.error = "Die KI-Schätzung konnte nicht geladen werden."
        }
    }

    private func save() async {
        guard let cents = draftCents else { return }
        saving = true
        error = nil
        defer { saving = false }
        var draft = RecipeDraft(recipe: recipe)
        draft.priceText = FoodMoney.entry(cents)
        draft.priceEstimated = estimated
        do {
            try await store.saveRecipe(id: recipe.id, expectedRevision: recipe.updatedAt, draft: draft, replacingIngredients: false)
        } catch let failure as RecipeSaveFailure {
            error = failure.message
        } catch {
            self.error = "Der Preis konnte nicht gespeichert werden."
        }
    }
}

struct MeatSymbol: Shape {
    // A drumstick with a tapered bone and two rounded ends.
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0.47, 0.64))
        path.addQuadCurve(to: point(0.38, 0.77), control: point(0.40, 0.70))
        path.addCurve(to: point(0.21, 0.96), control1: point(0.47, 0.93), control2: point(0.33, 1.03))
        path.addQuadCurve(to: point(0.15, 0.86), control: point(0.16, 0.92))
        path.addCurve(to: point(0.21, 0.67), control1: point(-0.03, 0.89), control2: point(0.01, 0.60))
        path.addQuadCurve(to: point(0.33, 0.55), control: point(0.29, 0.63))
        path.addCurve(to: point(0.53, 0.21), control1: point(0.35, 0.47), control2: point(0.40, 0.31))
        path.addCurve(to: point(0.89, 0.17), control1: point(0.64, 0.10), control2: point(0.80, 0.08))
        path.addCurve(to: point(0.92, 0.49), control1: point(0.98, 0.26), control2: point(0.99, 0.40))
        path.addCurve(to: point(0.47, 0.64), control1: point(0.82, 0.64), control2: point(0.65, 0.69))
        path.closeSubpath()
        return path
    }
}
