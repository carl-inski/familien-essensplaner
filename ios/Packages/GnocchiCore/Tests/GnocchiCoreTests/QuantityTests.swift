import Testing
@testable import GnocchiCore

struct QuantityTests {
    // Aus scaleAmount und scaledAmountText in lib/quantity.ts.
    @Test(arguments: [
        (1.25, "kg", 1.0, "1,25 kg", "1,25 kg"),
        (65.0, "g", 1.5, "65 g", "100 g"),
        (0.5, nil, 1.0, "½", "½"),
        (1.0, "Kugeln", 1.5, "1 Kugel (à 125 g)", "2 Kugeln (à 125 g)"),
        (240.0, "ml", 1.0, "1 cup (etwa 240 ml)", "240 ml (etwa 240 ml)"),
        (1.0, "EL", 0.25, "1 EL", "0,5 EL")
    ] as [(Double, String?, Double, String, String)])
    func sameDisplayAsWeb(amount: Double, unit: String?, factor: Double, text: String, expected: String) {
        let original = Quantity(amount: amount, unit: unit)
        let scaled = original.scaled(by: factor)
        #expect(scaled.displayText(originalText: text, original: original) == expected)
    }
}
