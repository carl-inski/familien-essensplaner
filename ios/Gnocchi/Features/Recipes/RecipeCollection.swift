import GnocchiCore
import SwiftUI

struct RecipeFilters: Equatable {
    static let unfiled = "ohne"
    static let favorites = "favoriten"
    var folder: String?
    var tag: String?
    var diet: String?
    var maxTime: Int?
    var book: String?
    var cooking: CookingFilter = .any

    enum CookingFilter: String, CaseIterable, Identifiable {
        case any, never, twoWeeks, fourWeeks, eightWeeks
        var id: Self { self }
        var days: Int? {
            switch self {
            case .any, .never: nil
            case .twoWeeks: 14
            case .fourWeeks: 28
            case .eightWeeks: 56
            }
        }
        var label: String {
            switch self {
            case .any: "Egal"
            case .never: "Nie gekocht"
            case .twoWeeks: "Seit 2 Wochen nicht"
            case .fourWeeks: "Seit 4 Wochen nicht"
            case .eightWeeks: "Seit 8 Wochen nicht"
            }
        }
    }

    func includes(_ recipe: Recipe, cooked: CookingSummary?, today: String) -> Bool {
        if folder == Self.unfiled {
            guard recipe.folderID == nil else { return false }
        } else if let folder, folder != Self.favorites, recipe.folderID != folder { return false }
        if let tag, recipe.tags?.contains(tag) != true { return false }
        if let diet, recipe.diet != diet { return false }
        if let maxTime, recipe.timeMin.map({ $0 <= maxTime }) != true { return false }
        if let book, recipe.cookbookID != book { return false }
        if cooking == .never && cooked != nil { return false }
        if let days = cooking.days, let cooked, cooked.latest > BerlinDay.adding(-days, to: today) { return false }
        return true
    }
}

enum RecipeOrder: String, CaseIterable, Identifiable {
    case alphabetical, recent, oldest, frequent, added
    var id: Self { self }
    var label: String {
        switch self {
        case .alphabetical: "A–Z"
        case .recent: "Zuletzt gekocht"
        case .oldest: "Am längsten nicht gekocht"
        case .frequent: "Am häufigsten gekocht"
        case .added: "Neu hinzugefügt"
        }
    }

    func sorted(_ recipes: [Recipe], history: [String: CookingSummary]) -> [Recipe] {
        recipes.sorted { a, b in
            let left = history[a.id]
            let right = history[b.id]
            switch self {
            case .alphabetical: break
            case .recent:
                if left?.latest != right?.latest { return (left?.latest ?? "") > (right?.latest ?? "") }
            case .oldest:
                if left?.latest != right?.latest { return (left?.latest ?? "") < (right?.latest ?? "") }
            case .frequent:
                if left?.count != right?.count { return (left?.count ?? 0) > (right?.count ?? 0) }
            case .added:
                if a.createdAt != b.createdAt { return (a.createdAt ?? "") > (b.createdAt ?? "") }
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}

struct CookingSummary {
    let latest: String
    let count: Int

    static func from(_ records: [CookingRecord]) -> [String: Self] {
        records.reduce(into: [:]) { summary, record in
            let old = summary[record.recipe_id]
            summary[record.recipe_id] = Self(latest: max(old?.latest ?? "", record.cooked_on), count: (old?.count ?? 0) + 1)
        }
    }
}

struct RecipeFilterView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: RecipeFilters
    @Binding var order: RecipeOrder

    var body: some View {
        Form {
            Section("Sammlung") {
                Picker("Ordner", selection: $filters.folder) {
                    Text("Alle").tag(nil as String?)
                    Text("Favoriten").tag(Optional(RecipeFilters.favorites))
                    Text("Ohne Ordner").tag(Optional(RecipeFilters.unfiled))
                    ForEach(store.folders) { Text($0.label).tag(Optional($0.id)) }
                }
                choices("Tag", selection: $filters.tag, values: store.recipes.flatMap { $0.tags ?? [] })
                Picker("Kochbuch", selection: $filters.book) {
                    Text("Alle").tag(nil as String?)
                    ForEach(store.cookbooks) { Text($0.title).tag(Optional($0.id)) }
                }
            }
            Section("Gericht") {
                Picker("Ernährung", selection: $filters.diet) {
                    Text("Alle").tag(nil as String?)
                    Text("Vegetarisch").tag(Optional("vegetarisch"))
                    Text("Fisch").tag(Optional("fisch"))
                    Text("Fleisch").tag(Optional("fleisch"))
                }
                Picker("Zeit", selection: $filters.maxTime) {
                    Text("Egal").tag(nil as Int?)
                    ForEach([20, 30, 60], id: \.self) { Text("Bis \($0) Min.").tag(Optional($0)) }
                }
                Picker("Kochhistorie", selection: $filters.cooking) {
                    ForEach(RecipeFilters.CookingFilter.allCases) { Text($0.label).tag($0) }
                }
            }
            Picker("Sortierung", selection: $order) {
                ForEach(RecipeOrder.allCases) { Text($0.label).tag($0) }
            }
            Button("Filter zurücksetzen") { filters = RecipeFilters() }
                .disabled(filters == RecipeFilters())
        }
        .navigationTitle("Filtern und sortieren")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
    }

    private func choices(_ label: String, selection: Binding<String?>, values: [String]) -> some View {
        Picker(label, selection: selection) {
            Text("Alle").tag(nil as String?)
            ForEach(Set(values).sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) {
                Text($0).tag(Optional($0))
            }
        }
    }
}

struct RecipeOrganizationView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipeID: String
    @State private var folderID: String?
    @State private var tags: [String]
    @State private var input = ""
    @State private var creatingFolder = false
    @State private var saving = false
    @State private var failed = false

    init(recipe: Recipe) {
        recipeID = recipe.id
        _folderID = State(initialValue: recipe.folderID)
        _tags = State(initialValue: (recipe.tags ?? []).reduce(into: []) { tags, tag in
            if !tags.contains(tag) { tags.append(tag) }
        })
    }

    private var enteredTags: [String] {
        input.components(separatedBy: ",").map(RecipeMarkdown.slugifyTag).filter { !$0.isEmpty }
    }

    private var suggestions: [String] {
        let counts = store.recipes.flatMap { $0.tags ?? [] }.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let term = RecipeMarkdown.slugifyTag(input)
        return Array(counts.keys.filter { !tags.contains($0) && (term.isEmpty || $0.contains(term)) }.sorted {
            let first = counts[$0, default: 0]
            let second = counts[$1, default: 0]
            if first != second { return first > second }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }.prefix(8))
    }

    var body: some View {
        Form {
            Section("Ordner") {
                Picker("Ordner", selection: $folderID) {
                    Text("Ohne Ordner").tag(nil as String?)
                    ForEach(store.folders) { Text($0.label).tag(Optional($0.id)) }
                }
                Button("Neuer Ordner", systemImage: "folder.badge.plus") { creatingFolder = true }
            }
            Section("Tags") {
                ForEach(tags, id: \.self) { tag in
                    HStack {
                        Text("#\(tag)")
                        Spacer()
                        Button("Tag \(tag) entfernen", systemImage: "minus.circle") { tags.removeAll { $0 == tag } }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Tag hinzufügen", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { add(enteredTags) }
                    Button("Hinzufügen", systemImage: "plus.circle.fill") { add(enteredTags) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(enteredTags.isEmpty)
                }
            }
            if !suggestions.isEmpty {
                Section("Tags aus der Sammlung") {
                    ForEach(suggestions, id: \.self) { tag in
                        Button("#\(tag)", systemImage: "plus") { add([tag]) }
                    }
                }
            }
        }
        .navigationTitle("Ordner und Tags")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(saving) }
            ToolbarItem(placement: .confirmationAction) { Button("Sichern") { Task { await save() } }.disabled(saving) }
        }
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .sheet(isPresented: $creatingFolder) {
            NavigationStack { FolderEditor(folder: nil) { folderID = $0 } }
                .presentationDragIndicator(.visible)
        }
        .alert("Ordner und Tags konnten nicht gespeichert werden.", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func add(_ newTags: [String]) {
        for tag in newTags where !tags.contains(tag) { tags.append(tag) }
        input = ""
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        add(enteredTags)
        do {
            try await store.organizeRecipe(id: recipeID, folderID: folderID, tags: tags)
            dismiss()
        } catch {
            failed = true
        }
    }
}

struct FolderEditor: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let folder: RecipeFolder?
    let onSave: (String?) -> Void
    @State private var id: String
    @State private var name: String
    @State private var icon: String
    @State private var busy = false
    @State private var deleting = false
    @State private var error: String?

    init(folder: RecipeFolder?, onSave: @escaping (String?) -> Void) {
        self.folder = folder
        self.onSave = onSave
        _id = State(initialValue: folder?.id ?? UUID().uuidString)
        _name = State(initialValue: folder?.name ?? "")
        _icon = State(initialValue: folder?.emoji ?? (folder == nil ? "📁" : ""))
    }

    var body: some View {
        Form {
            TextField("Ordnername", text: $name)
            Picker("Symbol", selection: $icon) {
                Text("Ohne Symbol").tag("")
                ForEach(symbols, id: \.self) { Text($0).tag($0) }
            }
            if let folder {
                Button("Ordner löschen", role: .destructive) { deleting = true }
                    .confirmationDialog("„\(folder.name)“ löschen?", isPresented: $deleting, titleVisibility: .visible) {
                        Button("Ordner löschen", role: .destructive) { Task { await save(deleting: true) } }
                    } message: {
                        Text("Die Rezepte bleiben in der Sammlung.")
                    }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(folder == nil ? "Neuer Ordner" : "Ordner bearbeiten")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { Task { await save(deleting: false) } }
                    .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40)
            }
        }
        .disabled(busy)
        .interactiveDismissDisabled(busy)
    }

    private var symbols: [String] {
        let standard = ["📁", "⭐️", "⚡️", "🍝", "🥗", "🍲", "🥘", "🍕", "🐟", "🥩", "🌱", "🧁", "🥞", "🎉", "👶", "🔥", "❄️", "🏕️"]
        if let current = folder?.emoji, !standard.contains(current) { return standard + [current] }
        return standard
    }

    private func save(deleting: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if deleting, let folder {
                try await store.deleteFolder(folder)
                onSave(nil)
            } else {
                try await store.saveFolder(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                           emoji: icon.isEmpty ? nil : icon, existing: folder != nil)
                onSave(id)
            }
            dismiss()
        } catch {
            self.error = "Der Ordner konnte nicht geändert werden."
        }
    }
}
