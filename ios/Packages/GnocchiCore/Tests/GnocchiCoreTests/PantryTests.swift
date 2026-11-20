import Testing
@testable import GnocchiCore

@Test("Vorratseinträge stimmen mit der Zutatenzerlegung der Web-App überein")
func pantryEntriesMatchWeb() {
    #expect(Pantry.entriesToAdd("Rinder- oder Gemüsebrühe") == ["rinder- oder gemüsebrühe"])
    #expect(Pantry.entriesFromInput("Tomaten, Olivenöl; Zucker\nSalz") == ["tomaten", "olivenöl", "zucker", "salz"])
    #expect(Pantry.entriesCovering("Meersalz, schwarzer Pfeffer", in: ["pfeffer", "salz"]) == ["pfeffer"])
}

@Test("Gemessener Vorrat nutzt dieselben Basiseinheiten wie die Web-App",
      arguments: [("1 kg Mehl", "Mehl", 1_000.0, "mehl|g"), ("0.5 l Milch", "Milch", 500.0, "milch|ml"),
                  ("2 Dosen Tomaten", "Tomaten", 2.0, "tomat|Dose"), ("etwa 500 g Reis", "Reis", 500.0, "rei|g")])
func measuredStockMatchesWeb(text: String, name: String, amount: Double, key: String) throws {
    let stock = try #require(Shopping.stockEntry(text))
    #expect(stock.name == name)
    #expect(stock.quantity?.amount == amount)
    #expect(stock.key == key)
    #expect(Shopping.stockEntry("Eier")?.quantity == nil)
}
struct PantryTests {
    // Aus lib/quantity.ts und lib/pantry.ts.
    @Test(arguments: [
        ("TK-Spinat", "spinat+tk"), ("Getrockneter Oregano", "oregano+trocken"),
        ("Basmati-Reis", "basmatirei"), ("Knoblauchzehen, gehackt", "knoblauchzeh"),
        ("frischer Koriander", "koriand"), ("Pfeffer (gemahlen)", "pfeff+gemahlen")
    ])
    func purchaseKeysMatchWeb(name: String, expected: String) {
        #expect(IngredientName.shoppingKey(name) == expected)
    }

    @Test(arguments: [
        ("Rinder- oder Gemüsebrühe", nil), ("Muskat, Salz, Pfeffer", "Muskat"),
        ("Meersalz, schwarzer Pfeffer", "Meersalz"), ("schwarzer Pfeffer", nil),
        ("Kokosnussöl oder Olivenöl", nil)
    ] as [(String, String?)])
    func pantryDeductionMatchesWeb(name: String, expected: String?) {
        let pantry: Set<String> = ["salz", "pfeffer", "olivenöl", "gemüsebrühe"]
        #expect(Pantry.remaining(name, in: pantry) == expected)
    }
}
