import GnocchiCore
import SwiftUI
import UniformTypeIdentifiers

struct RecipeMarkdownDocument: FileDocument {
    static let markdown = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [markdown] }
    private let data: Data

    init(recipe: Recipe, book: Cookbook?) {
        data = Data(AppShareText.withFooter(Self.markdown(recipe: recipe, book: book).text).utf8)
    }

    init(recipes: [Recipe], books: [Cookbook]) {
        let booksByID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        let documents = recipes.map { recipe in
            Self.markdown(recipe: recipe, book: recipe.cookbookID.flatMap { booksByID[$0] })
        }
        data = Data(AppShareText.withFooter(RecipeMarkdown.collectionText(documents)).utf8)
    }

    private static func markdown(recipe: Recipe, book: Cookbook?) -> RecipeMarkdown {
        var document = RecipeMarkdown(title: recipe.title)
        document.subtitle = recipe.subtitle
        document.source = recipe.source
        document.cookbook = book.map { ($0.title, recipe.cookbookPage) }
        document.tags = recipe.tags ?? []
        document.time = recipe.timeText
        document.servings = recipe.servings
        document.servingsText = recipe.servingsText
        document.ingredients = recipe.ingredients.sorted { $0.position < $1.position }.map {
            RecipeMarkdown.Ingredient(name: $0.name, amount: $0.amountText, group: $0.group)
        }
        document.steps = recipe.steps
        document.tip = recipe.tip
        let nutrition = RecipeDraft.nutritionDescription(recipe.nutrition)
        document.nutrition = nutrition.isEmpty ? nil : nutrition
        document.metadata = recipe.markdownMetadata
        return document
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
