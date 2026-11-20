import SwiftUI

struct CookbookRecipeLink: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let book: Cookbook
    @State private var search = ""

    var body: some View {
        List(store.recipes.matching(search)) { recipe in
            NavigationLink {
                CookbookLinkPage(recipe: recipe, book: book) { dismiss() }
            } label: {
                RecipeRow(recipe: recipe)
            }
        }
        .overlay {
            if store.recipes.isEmpty {
                ContentUnavailableView("Keine Rezepte vorhanden", systemImage: "book")
            } else if store.recipes.matching(search).isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle("Rezept verknüpfen")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Rezepte suchen")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        }
    }
}

struct CookbookLinkPage: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let book: Cookbook
    let finish: () -> Void
    let editingPage: Bool
    @State private var page: String
    @State private var confirmation = false
    @State private var busy = false
    @State private var error: String?

    init(recipe: Recipe, book: Cookbook, editingPage: Bool = false, finish: @escaping () -> Void) {
        self.recipe = recipe
        self.book = book
        self.editingPage = editingPage
        self.finish = finish
        _page = State(initialValue: recipe.cookbookID == book.id ? recipe.cookbookPage.map(String.init) ?? "" : "")
    }

    var body: some View {
        Form {
            LabeledContent("Rezept", value: recipe.title)
            LabeledContent("Kochbuch", value: book.title)
            TextField("Seitenzahl (optional)", text: $page).keyboardType(.numberPad)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(editingPage ? "Seitenzahl ändern" : "Seite angeben")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .toolbar {
            if editingPage {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark") { dismiss() }.disabled(busy)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editingPage ? "Sichern" : "Verknüpfen") {
                    if let currentBook = recipe.cookbookID, currentBook != book.id { confirmation = true }
                    else { Task { await save() } }
                }
                .disabled(busy || !validCookbookPage(page))
            }
        }
        .confirmationDialog("Kochbuch-Verknüpfung ersetzen?", isPresented: $confirmation, titleVisibility: .visible) {
            Button("Verknüpfung ersetzen") { Task { await save() } }
        }
    }

    private func save() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await store.linkRecipe(recipe, to: book, page: cookbookField(page).flatMap(Int.init),
                                       confirmed: !editingPage || recipe.bookConfirmed != false)
            finish()
        } catch let failure as CookbookError {
            error = failure.localizedDescription
        } catch {
            self.error = "Die Verknüpfung konnte nicht gespeichert werden."
        }
    }
}

struct CookbookReference: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let book: Cookbook
    @State private var id = UUID().uuidString
    @State private var title = ""
    @State private var page = ""
    @State private var diet = "vegetarisch"
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                TextField("Rezepttitel", text: $title)
                TextField("Seitenzahl (optional)", text: $page).keyboardType(.numberPad)
                Picker("Ernährungsweise", selection: $diet) {
                    Text("Vegetarisch").tag("vegetarisch")
                    Text("Fisch").tag("fisch")
                    Text("Fleisch").tag("fleisch")
                }
            } footer: {
                Text("Du kannst den Verweis sofort einplanen. Zutaten lassen sich später ergänzen.")
            }
            if failed { Text("Der Verweis konnte nicht angelegt werden.").foregroundStyle(.red) }
        }
        .navigationTitle("Verweis anlegen")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Anlegen") { Task { await save() } }
                    .disabled(busy || cookbookField(title) == nil || !validCookbookPage(page))
            }
        }
    }

    private func save() async {
        guard store.cookbooks.contains(where: { $0.id == book.id }) else {
            failed = true
            return
        }
        busy = true
        failed = false
        defer { busy = false }
        var draft = RecipeDraft()
        draft.title = title
        draft.diet = diet
        draft.servings = ""
        draft.cookbookID = book.id
        draft.cookbookPage = page
        do {
            try await store.saveRecipe(id: id, expectedRevision: nil, draft: draft, replacingIngredients: true)
            dismiss()
        } catch { failed = true }
    }
}

private func validCookbookPage(_ value: String) -> Bool {
    guard let text = cookbookField(value) else { return true }
    return Int32(text).map { $0 > 0 } ?? false
}
