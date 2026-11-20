import Testing
@testable import GnocchiCore

struct QuantityParsingTests {
    // Erwartete Werte aus parseAmount in lib/quantity.ts.
    @Test(arguments: [("2–3 EL", 3.0, "EL"), ("1½ kg", 1.5, "kg"), ("8 oz", 230.0, "g"),
                      ("¾ Tasse", 0.75, "Tasse"), ("7g", 7.0, "g"), ("1 cup", 240.0, "ml"),
                      ("2 Kugeln (à 125 g)", 2.0, "Kugeln"), ("1/2 Bund", 0.5, "Bund"),
                      ("½ to ¾ cup", 180.0, "ml"), ("100 bis 150 g", 150.0, "g")]
                      as [(String, Double, String?)])
    func parsingMatchesWeb(text: String, amount: Double, unit: String?) {
        #expect(Quantity.parseAmount(text) == Quantity(amount: amount, unit: unit))
        #expect(Quantity.parseAmount("nach Bedarf") == nil)
    }

    @Test("Mengenbereiche und Brüche bleiben beim Trennen von Zutaten erhalten")
    func writtenIngredientRanges() {
        let range = Quantity.splitIngredientLine("½ to ¾ cup heavy cream")
        #expect(range.amount == "½ to ¾ cup")
        #expect(range.name == "heavy cream")
        let fraction = Quantity.splitIngredientLine("1/2 Bund Petersilie")
        #expect(fraction.amount == "1/2 Bund")
        #expect(fraction.name == "Petersilie")
        let vague = Quantity.splitIngredientLine("etwas Speiseöl zum Ausbacken")
        #expect(vague.amount == "etwas")
        #expect(vague.name == "Speiseöl zum Ausbacken")
    }
}
