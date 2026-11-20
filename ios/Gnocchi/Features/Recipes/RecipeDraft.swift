import Foundation
import GnocchiCore
import Supabase

struct RecipeDraft: Equatable {
    struct Ingredient: Identifiable, Equatable {
        var id = UUID().uuidString
        var name = ""
        var amount = ""
        var group = ""
        var original: Quantity?
        var originalText: String?
        var aisle: String?

        init() {}

        init(_ ingredient: Recipe.Ingredient) {
            id = ingredient.id
            name = ingredient.name
            amount = ingredient.amountText ?? ""
            group = ingredient.group ?? ""
            original = ingredient.amount.map { Quantity(amount: $0, unit: ingredient.unit) }
            originalText = amount
            aisle = ingredient.aisle
        }

        var fields: AnyJSON {
            let value = amount.cleaned == originalText ? original : Quantity.parseAmount(amount)
            return .object([
                "name": .string(name.cleaned), "group_name": group.jsonText, "amount_text": amount.jsonText,
                "amount": value.map { .double($0.amount) } ?? .null,
                "unit": value?.unit.map(AnyJSON.string) ?? .null,
                "aisle": aisle.map(AnyJSON.string) ?? .null
            ])
        }
    }

    var title: String
    var subtitle: String
    var source: String
    var categoryText: String
    var tags: String
    var folderID: String?
    var diet: String?
    var timeText: String
    var timeMin: String
    var servings: String
    var servingsText: String
    var steps: String
    var tip: String
    var priceText = ""
    var priceEstimated = false
    private var originalPriceEstimated = false
    private var originalPriceText = ""
    private var originalExtraMetadata: JSONObject = [:]
    var nutritionText: String
    var nutritionEstimated: Bool
    private var originalNutritionText: String
    private let originalNutritionEstimated: Bool
    var cookbookID: String?
    var importedBook: Cookbook?
    var cookbookPage: String
    var bookConfirmed: Bool
    var imagePath: String?
    var importedCover: Data?
    var ingredients: [Ingredient]
    var missingPreparationIngredients: [String] = []
    var importedMetadata: [String: AnyJSON] = [:]

    var newCookbook: Cookbook? {
        importedBook.flatMap { $0.id == cookbookID ? $0 : nil }
    }

    init(recipe: Recipe? = nil) {
        title = recipe?.title ?? ""
        subtitle = recipe?.subtitle ?? ""
        source = recipe?.source ?? ""
        categoryText = recipe?.categories?.joined(separator: " / ") ?? ""
        tags = recipe?.tags?.joined(separator: ", ") ?? ""
        folderID = recipe?.folderID
        diet = recipe == nil ? "vegetarisch" : recipe?.diet
        timeText = recipe?.timeText ?? ""
        timeMin = recipe?.timeMin.map(String.init) ?? ""
        servings = recipe == nil ? "4" : recipe?.servings.map(String.init) ?? ""
        servingsText = recipe?.servingsText ?? ""
        steps = recipe?.steps.joined(separator: "\n\n") ?? ""
        tip = recipe?.tip ?? ""
        priceText = FoodMoney.entry(recipe?.pricePerServingCents)
        originalPriceText = priceText
        priceEstimated = recipe?.priceIsEstimate ?? false
        originalPriceEstimated = priceEstimated
        originalExtraMetadata = recipe?.extraMetadata?.objectValue ?? [:]
        let nutrition = Self.nutritionDescription(recipe?.nutrition)
        nutritionText = nutrition
        originalNutritionText = nutrition
        nutritionEstimated = recipe?.nutritionEstimated ?? false
        originalNutritionEstimated = nutritionEstimated
        cookbookID = recipe?.cookbookID
        cookbookPage = recipe?.cookbookPage.map(String.init) ?? ""
        bookConfirmed = recipe?.bookConfirmed ?? true
        imagePath = recipe?.imagePath
        ingredients = recipe?.ingredients.sorted { $0.position < $1.position }.map(Ingredient.init) ?? []
    }

    var valid: Bool {
        !title.cleaned.isEmpty && [servings, cookbookPage].allSatisfy { $0.cleaned.isEmpty || (Int($0.cleaned) ?? 0) > 0 }
            && (timeMin.cleaned.isEmpty || (Int(timeMin.cleaned) ?? -1) >= 0)
            && (priceText.cleaned.isEmpty || FoodMoney.cents(from: priceText) != nil)
    }

    var recipeFields: [String: AnyJSON] {
        let categories = categoryText.split(separator: "/").map { String($0).cleaned }.filter { !$0.isEmpty }
        let enteredTags = tags.split(separator: ",").map { String($0).cleaned }.filter { !$0.isEmpty }
        let tagValues = enteredTags.map(RecipeMarkdown.slugifyTag).filter { !$0.isEmpty }
        let directions = steps.components(separatedBy: "\n\n").map(\.cleaned).filter { !$0.isEmpty }
        var fields: [String: AnyJSON] = [
            "title": .string(title.cleaned), "subtitle": subtitle.jsonText, "source": source.jsonText,
            "categories": .array(categories.map(AnyJSON.string)), "tags": .array(tagValues.map(AnyJSON.string)),
            "folder_id": folderID.map(AnyJSON.string) ?? .null, "diet": diet.map(AnyJSON.string) ?? .null,
            "time_text": timeText.jsonText, "time_min": timeMin.jsonInteger,
            "servings": servings.jsonInteger, "servings_text": servingsText.cleaned.isEmpty ? servings.jsonText : servingsText.jsonText,
            "steps": .array(directions.map(AnyJSON.string)), "tip": tip.jsonText,
            "cookbook_id": cookbookID.map(AnyJSON.string) ?? .null,
            "cookbook_page": cookbookID == nil ? .null : cookbookPage.jsonInteger,
            "cookbook_link_confirmed": .bool(cookbookID == nil || bookConfirmed),
            "image_url": imagePath.map(AnyJSON.string) ?? .null
        ]
        let editedNutrition = nutritionText.cleaned != originalNutritionText.cleaned
        if editedNutrition {
            fields["nutrition"] = RecipeMarkdown.parseNutrition(nutritionText).map { .object($0.mapValues(AnyJSON.string)) } ?? .null
        }
        if nutritionEstimated != originalNutritionEstimated || (editedNutrition && nutritionText.cleaned.isEmpty) {
            fields["nutrition_estimated"] = .bool(!nutritionText.cleaned.isEmpty && nutritionEstimated)
        }
        if priceText.cleaned != originalPriceText.cleaned || priceEstimated != originalPriceEstimated ||
            importedMetadata["extra_meta"] != nil {
            var metadata = importedMetadata["extra_meta"]?.objectValue ?? originalExtraMetadata
            metadata["price_per_serving_cents"] = FoodMoney.cents(from: priceText).map(AnyJSON.integer)
            metadata["price_is_estimate"] = priceEstimated && !priceText.cleaned.isEmpty ? .bool(true) : nil
            fields["extra_meta"] = .object(metadata)
        }
        return fields.merging(importedMetadata) { existing, _ in existing }
    }

    var ingredientFields: [AnyJSON] {
        ingredients.filter { !$0.name.cleaned.isEmpty }.map(\.fields)
    }

    mutating func setPrice(from recipe: Recipe?) {
        priceText = FoodMoney.entry(recipe?.pricePerServingCents)
        originalPriceText = priceText
        priceEstimated = recipe?.priceIsEstimate ?? false
        originalPriceEstimated = priceEstimated
    }

    mutating func applyIngredientReview(_ review: RecipeIngredientReview) {
        var metadata = importedMetadata["extra_meta"]?.objectValue ?? originalExtraMetadata
        metadata["ingredient_emoji_aliases"] = review.metadata
        importedMetadata["extra_meta"] = .object(metadata)
        missingPreparationIngredients = review.missing
    }

    mutating func setImportedNutrition(_ values: AnyJSON?, replacingRecipe: Bool) {
        nutritionText = Self.nutritionDescription(values?.objectValue?.compactMapValues(\.stringValue))
        originalNutritionText = nutritionText
        importedMetadata["nutrition"] = replacingRecipe ? values ?? .null : values
        if replacingRecipe { importedMetadata["nutrition_estimated"] = .bool(false) }
    }

    static func nutritionDescription(_ values: [String: String]?) -> String {
        guard let values else { return "" }
        if let text = values["text"], !text.cleaned.isEmpty { return text }
        let energy = values["kcal"].map { "\($0) kcal" }
        let other = values.keys.filter { $0 != "text" && $0 != "kcal" }.sorted().compactMap { key in
            values[key].map { "\(key) \($0)" }
        }
        return ([energy].compactMap { $0 } + other).joined(separator: " | ")
    }
}

private extension String {
    var cleaned: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var jsonText: AnyJSON { cleaned.isEmpty ? .null : .string(cleaned) }
    var jsonInteger: AnyJSON { Int(cleaned).map(AnyJSON.integer) ?? .null }
}
