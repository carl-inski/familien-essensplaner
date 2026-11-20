import GnocchiCore
import SwiftUI

struct PantrySettings: View {
    @Environment(HouseholdStore.self) private var household
    @Environment(ShoppingStore.self) private var shopping
    let family: Membership
    @State private var adding = false

    var body: some View {
        List {
            Section("Immer zu Hause") {
                if shopping.pantry.isEmpty {
                    Text("Keine festen Vorräte").foregroundStyle(Theme.inkSecondary)
                }
                ForEach(shopping.pantry.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { name in
                    ShoppingIngredientRow(name: name.prefix(1).uppercased() + name.dropFirst())
                        .swipeActions {
                            Button("Entfernen", systemImage: "trash", role: .destructive) { remove(name) }
                                .disabled(shopping.saving)
                        }
                        .accessibilityAction(named: Text("Entfernen")) { remove(name) }
                }
            }
        }
        .listSectionSpacing(14)
        .navigationTitle("Vorrat")
        .navigationActionSurface()
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Vorrat hinzufügen", systemImage: "plus") { adding = true }
                    .disabled(shopping.saving)
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { ShoppingAddArticleSheet(target: .pantry) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Vorrat", isPresented: Binding(get: { shopping.error != nil }, set: { if !$0 { shopping.error = nil } })) {
            Button("OK", role: .cancel) { shopping.error = nil }
        } message: {
            Text(shopping.error ?? "")
        }
    }

    private func reload() async {
        guard !household.isDemo else { return }
        await shopping.load(family: family, members: household.members, today: BerlinDay.today())
    }

    private func remove(_ name: String) {
        Task { _ = await shopping.changePantry([name], adding: false, family: family, demo: household.isDemo) }
    }
}
