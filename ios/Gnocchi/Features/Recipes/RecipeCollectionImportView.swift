import SwiftUI

struct RecipeCollectionImportView: View {
    private enum Choice: String, CaseIterable {
        case skip = "Überspringen"
        case add = "Hinzufügen"
        case copy = "Als Kopie"
        case update = "Aktualisieren"
    }

    private struct Entry: Identifiable {
        let recipe: ImportedRecipe
        let original: Recipe?
        let choices: [Choice]
        var choice: Choice
        var failure: String?
        var id: UUID { recipe.id }

        func draft(books: [Cookbook]) -> RecipeDraft {
            var result = recipe.draft(books: books, replacing: choice == .update ? original : nil)
            if choice == .copy { result.title += " (Kopie)" }
            return result
        }
    }

    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [Entry]
    @State private var saving = false
    @State private var savedCount = 0
    @State private var showSummary = false
    let onSaved: (Set<UUID>) -> Void

    init(imports: [ImportedRecipe], existing: [Recipe], onSaved: @escaping (Set<UUID>) -> Void) {
        let byTitle = Dictionary(grouping: existing) { importTitleKey($0.title) }
        let importCounts = Dictionary(grouping: imports) { importTitleKey($0.title) }.mapValues(\.count)
        _entries = State(initialValue: imports.map { recipe in
            let title = importTitleKey(recipe.title)
            let matches = byTitle[title, default: []]
            if matches.isEmpty && importCounts[title] == 1 {
                return Entry(recipe: recipe, original: nil, choices: [.add, .skip], choice: .add)
            }
            let original = matches.count == 1 && importCounts[title] == 1 ? matches.first : nil
            return Entry(recipe: recipe, original: original,
                         choices: original == nil ? [.skip, .copy] : [.skip, .copy, .update], choice: .skip)
        })
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section {
                ForEach($entries) { $entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(entry.recipe.title, selection: $entry.choice) {
                            ForEach(entry.choices, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        if let book = entry.recipe.cookbook {
                            let page = book.page.map { ", S. \($0)" } ?? ""
                            let status = entry.recipe.matchingCookbook(in: store.cookbooks) == nil ? " · Neu im Regal" : ""
                            Text(book.title + page + status).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let failure = entry.failure {
                            Text(failure).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
            } footer: {
                Text("Vorhandene Rezepte werden zunächst übersprungen.")
            }
        }
        .navigationTitle("Importvorschau")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .navigationBarBackButtonHidden(saving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView().accessibilityLabel("Import läuft") }
                else {
                    Button("Importieren") { Task { await save() } }
                        .disabled(entries.allSatisfy { $0.choice == .skip })
                }
            }
        }
        .alert(savedCount == 1 ? "1 Rezept importiert" : "\(savedCount) Rezepte importiert",
               isPresented: $showSummary) {
            Button("OK") {
                if entries.allSatisfy({ $0.choice == .skip }) { dismiss() }
            }
        } message: {
            if entries.contains(where: { $0.failure != nil }) {
                Text("Bei den übrigen Rezepten steht der Fehler in der Liste.")
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        defer { saving = false }
        var saved: Set<UUID> = []
        let householdID = store.household?.id
        for index in entries.indices where entries[index].choice != .skip {
            guard householdID != nil, store.household?.id == householdID else { break }
            let entry = entries[index]
            let original = entry.choice == .update ? entry.original : nil
            let draft = entry.draft(books: store.cookbooks)
            entries[index].failure = nil
            guard draft.valid, original == nil || original?.updatedAt != nil else {
                entries[index].failure = "Öffne den Entwurf einzeln und prüfe die Angaben."
                continue
            }
            do {
                try await store.saveRecipe(id: original?.id ?? entry.id.uuidString, expectedRevision: original?.updatedAt,
                                           draft: draft, replacingIngredients: true, refresh: false)
                saved.insert(entry.id)
            } catch let failure as RecipeSaveFailure {
                entries[index].failure = failure.message
            } catch {
                entries[index].failure = "Das Rezept konnte nicht gesichert werden."
            }
        }
        await store.load()
        entries.removeAll { saved.contains($0.id) }
        savedCount = saved.count
        onSaved(saved)
        showSummary = true
    }
}
