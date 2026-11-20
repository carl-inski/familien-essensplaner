import Testing
import GnocchiCore

@Test("Rezeptdatei entspricht dem Export der Web-App")
func recipeMarkdownMatchesWeb() throws {
    var recipe = RecipeMarkdown(title: "Suppe")
    recipe.subtitle = "Für kalte Tage"
    recipe.source = "Familienheft"
    recipe.cookbook = ("Winterküche", 42)
    recipe.categories = ["Suppen & Eintöpfe"]
    recipe.tags = ["winter"]
    recipe.time = "25 Min"
    recipe.servings = 4
    recipe.servingsText = "4 Portionen"
    recipe.ingredients = [.init(name: "Karotten", amount: "300 g", group: "Für die Suppe")]
    recipe.steps = ["Karotten garen."]
    recipe.tip = "Pürieren."
    recipe.nutrition = "120 kcal | Eiweiß 3 g"
    recipe.metadata = [
        .init(key: "Saison", value: "Winter", position: .head),
        .init(key: "Vorrat", value: "Einfrieren", position: .tail)
    ]

    // lib/markdown.ts: recipeToMarkdown(...) + "\n"
    let expected = [
        "## Suppe", "", "**Untertitel:** Für kalte Tage  ", "**Quelle:** Familienheft  ",
        "**Kochbuch:** Winterküche, S. 42  ", "**Kategorie:** Suppen & Eintöpfe  ",
        "**Tags:** winter  ", "**Zeit:** 25 Min  ", "**Portionen:** 4 Portionen  ", "**Saison:** Winter  ",
        "", "### Zutaten", "", "| Zutat | Menge |", "|---|---|", "| **Für die Suppe** | |", "| Karotten | 300 g |",
        "", "### Zubereitung", "", "1. Karotten garen.", "", "**Tipp:** Pürieren.",
        "", "**Nährwerte pro Portion:** 120 kcal | Eiweiß 3 g", "", "**Vorrat:** Einfrieren", ""
    ].joined(separator: "\n")
    #expect(recipe.text == expected)
    let collection = "# Rezeptsammlung\r\n\r\n## Inhalt\r\n\r\n---\r\n\r\n" + expected
    let imported = try #require(RecipeMarkdown.parseCollection(collection).first)
    #expect(imported.text == expected)
    #expect(imported.timeMinutes == 25)
    #expect(imported.nutritionValues?["kcal"] == "120")
    #expect(imported.nutritionValues?["Eiweiß"] == "3 g")
    #expect(imported.diet == "vegetarisch")
}

@Test("Export einer Sammlung mit mehr als 50 Rezepten ist vollständig importierbar")
func recipeCollectionRoundTrip() throws {
    let recipes = (1...53).map { RecipeMarkdown(title: "Suppe & Gemüse \($0)") }
    let text = RecipeMarkdown.collectionText(recipes)
    #expect(text.hasPrefix("# Rezeptsammlung\n\n## Inhalt\n\n1. [Suppe & Gemüse 1](#suppe--gemüse-1)\n"))
    let imported = try RecipeMarkdown.parseCollection(text)
    #expect(imported.map(\.title) == recipes.map(\.title))
    #expect(RecipeMarkdown.collectionText(imported) == text)
}
