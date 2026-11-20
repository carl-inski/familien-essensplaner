import SwiftUI

enum RecipeAction: String {
    case schedule, organize, ask, export, edit, delete
}

struct RecipeActionRequest: Identifiable {
    let recipe: Recipe
    let action: RecipeAction
    var id: String { "\(recipe.id)/\(action.rawValue)" }
}

struct RecipeActionMenu<StackActions: View>: View {
    let url: URL
    let perform: (RecipeAction) -> Void
    @ViewBuilder var stackActions: () -> StackActions

    var body: some View {
        Button("Zur Woche hinzufügen", systemImage: "calendar.badge.plus") { perform(.schedule) }
        Button("Ordner und Tags", systemImage: "folder") { perform(.organize) }
        Button("KI befragen", systemImage: "sparkles") { perform(.ask) }
        Menu("Teilen", systemImage: "square.and.arrow.up") {
            ShareLink(item: AppShareText.withFooter(url.absoluteString)) {
                Label("Rezeptlink teilen", systemImage: "link")
            }
            Button("Als Markdown exportieren", systemImage: "doc.text") { perform(.export) }
        }
        .menuOrder(.fixed)
        stackActions()
        Divider()
        Button("Bearbeiten", systemImage: "pencil") { perform(.edit) }
        Button("Löschen", systemImage: "trash", role: .destructive) { perform(.delete) }
    }
}

extension Recipe {
    func sharingURL(servings: Int? = nil) -> URL {
        let url = Backend.site.appending(path: "r").appending(path: publicSlug)
        guard let servings else { return url }
        return url.appending(queryItems: [URLQueryItem(name: "p", value: String(servings))])
    }
}

extension View {
    func recipeActions(_ request: Binding<RecipeActionRequest?>, onDelete: @escaping () -> Void = {}) -> some View {
        modifier(RecipeActionPresentation(request: request, onDelete: onDelete))
    }

    func compactRecipeSheet() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}

private struct RecipeActionPresentation: ViewModifier {
    @Environment(HouseholdStore.self) private var store
    @Environment(AssistantStore.self) private var assistant
    @Binding var request: RecipeActionRequest?
    var onDelete: () -> Void
    @State private var deleting = false
    @State private var error: String?

    private var presentedSheet: Binding<RecipeActionRequest?> {
        Binding(
            get: {
                guard let request, request.action != .delete, request.action != .export else { return nil }
                return request
            },
            set: {
                if $0 == nil, let action = request?.action, action != .delete, action != .export {
                    request = nil
                }
            }
        )
    }

    private func presents(_ action: RecipeAction) -> Binding<Bool> {
        Binding(
            get: { request?.action == action },
            set: { if !$0 && request?.action == action { request = nil } }
        )
    }

    private var exportRecipe: Recipe? { request?.action == .export ? request?.recipe : nil }
    private var exportFilename: String {
        guard let title = exportRecipe?.title else { return "Rezept.md" }
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.newlines))
            .joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return "\(cleaned.isEmpty ? "Rezept" : String(cleaned.prefix(70))).md"
    }

    func body(content: Content) -> some View {
        content
            .disabled(deleting)
            .sheet(item: presentedSheet) { route in
                NavigationStack {
                    switch route.action {
                    case .schedule: RecipeScheduleView(recipe: route.recipe)
                    case .organize: RecipeOrganizationView(recipe: route.recipe)
                    case .ask:
                        AssistantView(store: assistant, recipe: route.recipe)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Schließen") { request = nil }
                                }
                            }
                    case .edit: RecipeEditor(recipe: route.recipe)
                    case .export, .delete: EmptyView()
                    }
                }
                .presentationDetents(route.action == .schedule || route.action == .organize ? [.medium, .large] : [.large])
                .presentationDragIndicator(.visible)
            }
            .fileExporter(isPresented: presents(.export), document: exportRecipe.map { recipe in
                RecipeMarkdownDocument(recipe: recipe, book: store.cookbooks.first { $0.id == recipe.cookbookID })
            }, contentType: RecipeMarkdownDocument.markdown, defaultFilename: exportFilename) { result in
                if case .failure = result { error = "Das Rezept konnte nicht exportiert werden." }
            }
            .confirmationDialog("„\(request?.recipe.title ?? "")“ löschen?", isPresented: presents(.delete),
                                titleVisibility: .visible, presenting: request?.recipe) { recipe in
                Button("Rezept löschen", role: .destructive) { Task { await remove(recipe) } }
            } message: { _ in
                Text("Auch die Rezeptnotizen und der Kochverlauf zu diesem Rezept werden gelöscht.")
            }
            .alert(error ?? "", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            }
    }

    private func remove(_ recipe: Recipe) async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await store.deleteRecipe(recipe)
            onDelete()
        } catch {
            self.error = "Das Rezept konnte nicht gelöscht werden."
        }
    }
}
