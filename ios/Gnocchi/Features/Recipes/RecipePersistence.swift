import Foundation
import Supabase

enum RecipeSaveFailure: Error {
    case noHousehold, stale

    var message: String {
        switch self {
        case .noHousehold: "Die Familie ist gerade nicht verfügbar."
        case .stale: "Das Rezept wurde inzwischen geändert. Öffne die aktuelle Fassung, bevor du es erneut bearbeitest."
        }
    }
}

extension HouseholdStore {
    func saveRecipe(id: String, expectedRevision: String?, draft: RecipeDraft, replacingIngredients: Bool,
                    refresh: Bool = true) async throws {
        guard let household else { throw RecipeSaveFailure.noHousehold }
        if isDemo {
            if expectedRevision == nil, recipes.contains(where: { $0.id == id }) { return }
            var resolved = draft
            let book = draft.newCookbook
            let existing = book.flatMap { pending in
                cookbooks.first { $0.title.caseInsensitiveCompare(pending.title) == .orderedSame }
            }
            if let existing { resolved.cookbookID = existing.id }
            try saveDemoRecipe(id: id, expectedRevision: expectedRevision, draft: resolved, replacingIngredients: replacingIngredients)
            if let book, existing == nil { try await saveCookbook(book, existing: false) }
            return
        }
        var parameters: [String: AnyJSON] = [
            "p_id": .string(id),
            "p_household": .string(household.id),
            "p_expected_updated_at": expectedRevision.map(AnyJSON.string) ?? .null,
            "p_recipe": .object(draft.recipeFields),
            "p_ingredients": replacingIngredients ? .array(draft.ingredientFields) : .null
        ]
        if let book = draft.newCookbook { parameters["p_book_title"] = .string(book.title) }
        do {
            try await Backend.client.rpc(draft.newCookbook == nil ? "ep_save_recipe" : "ep_save_recipe_with_cookbook",
                                         params: parameters).execute()
        } catch let error as PostgrestError where error.code == "40001" {
            // Refresh the parent screen, preserving the local draft in the sheet.
            if refresh { await load() }
            throw RecipeSaveFailure.stale
        }
        if refresh { await load() }
    }

    func uploadRecipePhoto(_ data: Data) async throws -> String {
        guard let household, !isDemo else { throw RecipeSaveFailure.noHousehold }
        let bucket = Backend.client.storage.from("ep-images")
        let path = "\(household.id)/\(UUID().uuidString).jpg"
        let url = try bucket.getPublicURL(path: path)
        try await bucket.upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return url.absoluteString
    }
}
