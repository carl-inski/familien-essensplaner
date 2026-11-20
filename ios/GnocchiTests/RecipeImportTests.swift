import Foundation
import Testing
@testable import Gnocchi

@Suite("Rezeptimport")
struct RecipeImportTests {
    @Test("Teilimporte übernehmen nur im Beitrag belegte Zutaten")
    func captionPartialNeedsEvidence() throws {
        let response = #"{"title":"Pasta","ingredients":[{"name":"Nudeln","quote":"macaroni"},{"name":"Sahne","quote":"cream"},{"name":"Käse","quote":"cheese"},{"name":"Knoblauch","quote":"garlic"}]}"#
        let text = "Layers of macaroni, cream and cheese."
        let draft = try #require(RecipeImportService.captionDraft(response, text: text, source: "https://example.org"))
        #expect(draft.ingredients.map(\.name) == ["Nudeln", "Sahne", "Käse"])
        #expect(draft.steps.isEmpty)
        #expect(draft.ingredients.allSatisfy { $0.amount == nil })
        #expect(RecipeImportService.captionDraft(response, text: "Pasta mit Eiscreme und Käse.", source: "https://example.org") == nil)
    }

    @Test("Der ergänzte Link muss allein stehen und vom ursprünglichen Beitrag abweichen")
    func supplementalRecipeLink() {
        let original = "https://www.instagram.com/reel/ABC/"
        let recipe = "https://example.org/rezepte/suppe"
        #expect(RecipeImportService.supplementalRecipeLink(" \(recipe)\n", original: original) == recipe)
        #expect(RecipeImportService.supplementalRecipeLink(original, original: original) == nil)
        #expect(RecipeImportService.supplementalRecipeLink("Rezepttext \(recipe)", original: original) == nil)
        #expect(RecipeImportService.supplementalRecipeLink("https://user:pass@example.org/rezept", original: original) == nil)
    }

    private let recipe = #"{"title":"Suppe","source":"https://example.org/rezept","categories":[],"tags":[],"ingredients":[{"name":"Wasser","amount":1.5,"unit":"l"}],"steps":["Aufkochen."],"cookbook":{"title":"Mein Buch","page":12}}"#

    @Test("Importantwort erhält Quelle, Mengen, Buch und Warnungen")
    func response() throws {
        let result = try RecipeImportService.decode(Data("{\"draft\":\(recipe),\"warnings\":[\"Mengen prüfen\"]}".utf8), statusCode: 200)
        let imported = try #require(result.drafts.first)
        let draft = imported.draft(books: [])
        #expect(draft.source == "https://example.org/rezept")
        #expect(draft.ingredients.first?.amount == "1,5 l")
        if case .object(let fields) = draft.ingredients.first?.fields {
            #expect(fields["amount"] == .double(1.5))
        } else { Issue.record("Zutatenfelder fehlen") }
        #expect(draft.newCookbook?.title == "Mein Buch")
        #expect(draft.cookbookPage == "12")
        #expect(!draft.bookConfirmed)
        #expect(result.warnings == ["Mengen prüfen"])
    }

    @Test("Der Emoji-Katalog enthält mindestens 1.000 einzelne Suchbegriffe")
    @MainActor func ingredientEmojiCatalog() {
        #expect(IngredientEmojiCatalog.entries.count >= 1_000)
        #expect(IngredientEmojiCatalog.terms.contains { $0.name == "Süßkartoffel" && $0.emoji == "🥔" })
        #expect(IngredientEmojiCatalog.terms.contains { $0.name == "Sprosse" && $0.illustration == "ingredient-sprouts" })
        #expect(IngredientEmojiCatalog.entries.values.allSatisfy {
            $0.count == 1 && $0.unicodeScalars.first?.properties.isEmoji == true
        })
        #expect(IngredientEmojiCatalog.emoji(for: "Eier") == "🥚")
        #expect(IngredientEmojiCatalog.emoji(for: "frisch gehackter Koriander") == "🌿")
        #expect(IngredientEmojiCatalog.emoji(for: "Reisbandnudeln (dünn)") == "🍝")
        #expect(IngredientIcon(name: "Reispapierblätter (22 cm Ø)", aisle: nil).hasCatalogIcon)
        #expect(IngredientEmojiCatalog.missingNames(in: [
            "Garnelen (gekocht) oder Hähnchenbrust", "Kartoffeln oder Fantasieknolle",
            "TK-Blattspinat", "Gochujang", "Hähnchenbrust oder -schenkel",
            "Speiseöl zum Ausbacken", "Reife Kirschtomaten in verschiedenen Farben",
            "flüssiger Honig", "ungesalzene Pistazienkerne"
        ]) == ["Fantasieknolle"])
    }

    @Test("Eigene Zwiebel-Emojis behalten bei Plural die Zuordnung")
    @MainActor func generatedIngredientEmoji() throws {
        #expect(IngredientEmojiCatalog.terms.allSatisfy { $0.hasGeneratedImage })
        let onion = try #require(IngredientEmojiCatalog.generatedKey(for: "Zwiebeln"))
        let redOnion = try #require(IngredientEmojiCatalog.generatedKey(for: "rote Zwiebeln"))
        #expect(onion == "zwiebel")
        #expect(redOnion == "rotezwiebel")
        #expect(IngredientEmojiImages.image(for: onion)?.size.width == 96)
        #expect(IngredientEmojiImages.image(for: redOnion)?.size.width == 96)
    }

    @Test("Die Vollbildvorschau übernimmt bearbeitete Mengen und den Original-Link")
    func importedPreview() throws {
        let result = try RecipeImportService.decode(Data("{\"draft\":\(recipe)}".utf8), statusCode: 200)
        var draft = try #require(result.drafts.first).draft(books: [])
        draft.title = "Suppe für zwei"
        draft.ingredients[0].amount = "2 l"
        let preview = try draft.previewRecipe(id: "preview")
        #expect(preview.id == "preview")
        #expect(preview.title == "Suppe für zwei")
        #expect(preview.source == "https://example.org/rezept")
        #expect(preview.ingredients.first?.amount == 2)
        #expect(preview.ingredients.first?.id == draft.ingredients[0].id)
        #expect(preview.steps == ["Aufkochen."])
    }

    @Test("Eine gesperrte Quelle fordert Ergänzungen an")
    func supplement() throws {
        let data = Data(#"{"error":"Beschreibung ergänzen","needs_input":true}"#.utf8)
        do {
            _ = try RecipeImportService.decode(data, statusCode: 422)
            Issue.record("Fehlerantwort wurde als Rezept angenommen")
        } catch let error as RecipeImportFailure {
            #expect(error.needsInput)
            #expect(error.message == "Beschreibung ergänzen")
        }
    }

    @Test("Leere und ungültige Antworten werden nicht als erfolgreicher Import behandelt", arguments: ["{}", "<html>Fehler</html>", #"{"drafts":[]}"#])
    func invalidResponse(_ body: String) {
        #expect(throws: RecipeImportFailure.self) {
            try RecipeImportService.decode(Data(body.utf8), statusCode: 200)
        }
    }

    @Test("Der Demo-Import speichert die tatsächliche Quelle und ignoriert nachgestellten Modelltext")
    func demoLinkSource() throws {
        let url = "https://www.instagram.com/reel/beispiel/"
        let result = try RecipeImportService.decodeDemoDrafts("{\"drafts\":[\(recipe)]}\nViel Spaß beim Kochen!", source: url)
        let imported = try #require(result.drafts.first)
        #expect(imported.source == url)
        #expect(imported.draft(books: []).ingredients.first?.amount == "1,5 l")
        #expect(imported.steps == ["Aufkochen."])
    }

    @Test("Ein defekter zweiter Entwurf verwirft kein vollständiges Rezept")
    func keepsCompleteDemoRecipeWithTextQuantities() throws {
        let response = #"{"drafts":[null,{"title":"Suppe","servings":"2","ingredients":[{"name":"Wasser","amount":"1,5","unit":"l"}],"steps":["Kochen."]}]}"#
        let result = try RecipeImportService.decodeDemoDrafts(response, source: nil)
        let imported = try #require(result.drafts.first)
        #expect(result.drafts.count == 1)
        #expect(imported.servings == 2)
        #expect(imported.ingredients.first?.amount == 1.5)
        #expect(imported.draft(books: []).ingredients.first?.amount == "1,5 l")
    }

    @Test("Die Übersetzung behält Mengenbereiche und Einheiten aus dem Original")
    func translatedRecipeKeepsOriginalQuantities() throws {
        let original = #"{"drafts":[{"title":"Pasta","ingredients":[{"name":"Heavy cream","amount":0.75,"unit":"cup","amount_text":"½–¾ cup"}],"steps":["Stir."]}]}"#
        let german = #"{"drafts":[{"title":"Pasta","ingredients":[{"name":"Sahne","amount":120,"unit":"ml","source_index":0}],"steps":["Rühren."]}]}"#
        let source = try #require(RecipeImportService.decodeDemoDrafts(original, source: nil).drafts.first)
        let translation = try #require(RecipeImportService.decodeDemoDrafts(german, source: nil).drafts.first)
        let draft = try #require(RecipeImportService.preservingOriginalQuantities(source, in: translation))
        #expect(draft.ingredients.first?.name == "Sahne")
        #expect(draft.ingredients.first?.amount_text == "½–¾ cup")
        #expect(draft.ingredients.first?.unit == "cup")
    }
}
