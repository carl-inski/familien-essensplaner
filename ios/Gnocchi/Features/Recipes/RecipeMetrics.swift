import SwiftUI

enum FoodMoney {
    static let maxCents = 10_000_000

    static func cents(from input: String) -> Int? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^\d{1,6}([,.]\d{1,2})?$"#, options: .regularExpression) != nil,
              let amount = Decimal(string: value.replacingOccurrences(of: ",", with: "."),
                                   locale: Locale(identifier: "en_US_POSIX")),
              amount * 100 <= Decimal(maxCents) else { return nil }
        return NSDecimalNumber(decimal: amount * 100).intValue
    }

    static func amount(_ cents: Int) -> Decimal { Decimal(cents) / 100 }

    static func entry(_ cents: Int?) -> String {
        cents.map { amount($0).formatted(.number.grouping(.never).precision(.fractionLength(2))) } ?? ""
    }
}

struct RecipeRating: Decodable, Identifiable, Sendable {
    let memberID: String
    let stars: Int
    var id: String { memberID }

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case stars
    }
}

struct RecipeRatingTile: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let recipeID: String
    @State private var ratings: [RecipeRating] = []
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?

    private static let gold = Color(red: 1, green: 0.77, blue: 0.25)

    private var mine: Int { ratings.first { $0.memberID == store.household?.memberID }?.stars ?? 0 }

    var body: some View {
        RecipePanel("Bewertung") {
            HStack(spacing: 0) { stars }
                .disabled(!loaded || saving)
            ForEach(ratings.filter { $0.memberID != store.household?.memberID }) { rating in
                let name = store.members.first { $0.id == rating.memberID }?.name ?? "Familienmitglied"
                HStack {
                    Text(name).font(.subheadline)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { index in
                            Image(systemName: index <= rating.stars ? "star.fill" : "star")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(Self.gold)
                    .accessibilityLabel("\(rating.stars) von 5 Sternen")
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Theme.recipeSecondary)
                if !loaded {
                    Button("Erneut laden") { Task { await reload() } }
                }
            } else if !loaded {
                ProgressView("Bewertungen werden geladen")
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active, !saving { await reload() }
        }
    }

    private var stars: some View {
        ForEach(1...5, id: \.self) { value in
            Button {
                Task { await rate(value) }
            } label: {
                Image(systemName: value <= mine ? "star.fill" : "star")
                    .font(.title2.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Self.gold)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(value == 1 ? "1 Stern geben" : "\(value) Sterne geben")
            .accessibilityAddTraits(value == mine ? .isSelected : [])
        }
    }

    private func reload() async {
        do {
            let result = try await store.loadRatings(for: recipeID)
            guard !Task.isCancelled, !saving else { return }
            ratings = result
            loaded = true
            error = nil
        } catch {
            if !Task.isCancelled { self.error = "Bewertungen konnten nicht geladen werden." }
        }
    }

    private func rate(_ value: Int) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let rating = try await store.saveRating(value, for: recipeID)
            ratings.removeAll { $0.memberID == rating.memberID }
            ratings.append(rating)
            error = nil
        } catch {
            self.error = "Die Bewertung konnte nicht gespeichert werden."
        }
    }
}

struct WeeklyBudgetSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HouseholdStore.self) private var store
    let family: Membership
    @State private var text = ""
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Betrag in Euro", text: $text)
                    .keyboardType(.decimalPad)
                    .disabled(!loaded || saving)
            } footer: {
                Text("Das Budget gilt für die ganze Familie. Ein leeres Feld entfernt die Budgetgrenze.")
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    if !loaded { Button("Erneut laden") { Task { await load() } } }
                }
            }
        }
        .navigationTitle("Wochenbudget")
        .gnScreen()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { Task { await save() } }
                    .disabled(!loaded || saving || (!text.isEmpty && (FoodMoney.cents(from: text) ?? 0) == 0))
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            text = FoodMoney.entry(try await store.loadWeeklyBudget(for: family))
            loaded = true
            error = nil
        } catch {
            if !Task.isCancelled { self.error = "Das Budget konnte nicht geladen werden." }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await store.saveWeeklyBudget(FoodMoney.cents(from: text), for: family)
            dismiss()
        } catch {
            self.error = "Das Budget konnte nicht gespeichert werden."
        }
    }
}

enum RecipeNutrient: String, CaseIterable, Identifiable {
    case energy, protein, carbohydrates, fat

    var id: Self { self }

    var label: String {
        switch self {
        case .energy: "Energie"
        case .protein: "Eiweiß"
        case .carbohydrates: "Kohlenhydrate"
        case .fat: "Fett"
        }
    }

    var unit: String { self == .energy ? "kcal" : "g" }

    var keys: [String] {
        switch self {
        case .energy: ["kcal", "energie", "kalorien", "calories", "energy"]
        case .protein: ["eiweiß", "eiweiss", "protein"]
        case .carbohydrates: ["kohlenhydrate", "carbohydrates", "carbs"]
        case .fat: ["fett", "fat"]
        }
    }

    func amount(in recipe: Recipe) -> Double? {
        let entries = recipe.nutrition ?? [:]
        let base = entries.sorted { $0.key < $1.key }
        for key in keys {
            guard let raw = base.first(where: { $0.key.lowercased() == key })?.value else { continue }
            let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let value = normalized.hasSuffix(unit)
                ? normalized.dropLast(unit.count).trimmingCharacters(in: .whitespaces)
                : normalized
            if let amount = Double(value.replacingOccurrences(of: ",", with: ".")), amount.isFinite, amount >= 0 {
                return amount
            }
        }
        return nil
    }
}
