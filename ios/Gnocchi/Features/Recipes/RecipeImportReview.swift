import GnocchiCore
import Supabase
import SwiftUI

struct RecipeImportReview: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecipeDraft
    @State private var saved: Recipe?
    @State private var saving = false
    @State private var editing = false
    @State private var modified = false
    @State private var confirmingDiscard = false
    @State private var uploadedCover: String?
    @State private var error: String?
    @State private var id: String
    private let original: Recipe?
    private let warnings: [String]
    private let onSaved: () -> Void

    init(draft: RecipeDraft, original: Recipe?, folderID: String?, warnings: [String], onSaved: @escaping () -> Void) {
        var draft = draft
        if original == nil, let folderID, folderID != RecipeFilters.unfiled { draft.folderID = folderID }
        _draft = State(initialValue: draft)
        self.original = original
        self.warnings = warnings
        self.onSaved = onSaved
        _id = State(initialValue: original?.id ?? UUID().uuidString)
    }

    var body: some View {
        NavigationStack {
            if let saved {
                RecipeDetailView(recipe: saved, coverData: store.isDemo ? draft.importedCover : nil)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Fertig", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                        }
                    }
            } else if let preview = try? draft.previewRecipe(id: id) {
                RecipeDetailView(recipe: preview, coverData: draft.importedCover, review: .init(
                    warnings: warnings,
                    saving: saving,
                    canSave: draft.valid,
                    edit: { editing = true },
                    save: { Task { await save() } }
                ))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Zurück zum Import", systemImage: "chevron.left") {
                            if modified { confirmingDiscard = true } else { dismiss() }
                        }
                        .labelStyle(.iconOnly)
                        .disabled(saving)
                    }
                }
                .navigationDestination(isPresented: $editing) {
                    RecipeEditor(recipe: original, imported: draft, applyDraft: { updated in
                        if draft.importedCover != updated.importedCover { uploadedCover = nil }
                        draft = updated
                        modified = true
                    })
                }
            } else {
                ContentUnavailableView("Entwurf konnte nicht geöffnet werden", systemImage: "doc.text")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Zurück zum Import") { dismiss() }
                        }
                    }
            }
        }
        .interactiveDismissDisabled(saving || (saved == nil && modified))
        .confirmationDialog("Änderungen am Entwurf verwerfen?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) { dismiss() }
            Button("Weiter bearbeiten", role: .cancel) {}
        }
        .alert("Rezept", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func save() async {
        guard draft.valid, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            var candidate = draft
            if let cover = draft.importedCover, !store.isDemo {
                if uploadedCover == nil {
                    let jpeg = RecipePhoto.jpeg(from: cover, maxPixelSize: 2_000) ?? cover
                    uploadedCover = try await store.uploadRecipePhoto(jpeg)
                }
                candidate.imagePath = uploadedCover
            }
            let preview = try candidate.previewRecipe(id: id)
            try await store.saveRecipe(id: id, expectedRevision: original?.updatedAt, draft: candidate,
                                       replacingIngredients: true)
            saved = store.recipes.first { $0.id == id } ?? preview
            onSaved()
        } catch let failure as RecipeSaveFailure {
            error = failure.message
        } catch {
            self.error = "Das Rezept konnte nicht gesichert werden. Dein Entwurf ist noch da."
        }
    }
}

extension RecipeDraft {
    func previewRecipe(id: String) throws -> Recipe {
        var fields = recipeFields
        fields["id"] = .string(id)
        fields["public_slug"] = .string(id)
        fields["ep_recipe_ingredients"] = .array(
            ingredients.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .enumerated().map { index, ingredient in
                    var row = ingredient.fields.objectValue ?? [:]
                    row["id"] = .string(ingredient.id)
                    row["position"] = .integer(index)
                    return .object(row)
                }
        )
        return try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(fields))
    }
}
