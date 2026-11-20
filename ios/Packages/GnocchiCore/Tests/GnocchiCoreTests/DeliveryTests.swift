// Gleichlauf mit lib/delivery.ts: Erwartungswerte mit tsx aus shopSearchTerm/shopSearchUrl erzeugt.

import Testing
@testable import GnocchiCore

@Suite("Lieferdienst-Suche wie die Web-App")
struct DeliveryTests {
    static let cases: [(String, String)] = [
        ("480 g Hähnchenschenkel (ohne Knochen/Haut)", "Hähnchenschenkel"),
        ("2 Zwiebeln", "Zwiebeln"),
        ("1,5 l Milch", "Milch"),
        ("1 TL Olivenöl", "Olivenöl"),
        ("½ Bund Petersilie", "Petersilie"),
        ("3 Zehen Knoblauch, fein gehackt", "Knoblauch"),
        ("ca. 200 g Feta", "Feta"),
        ("2-3 Möhren", "Möhren"),
        ("4 Große Tortillas", "Tortillas"),
        ("1 Dose Kokosmilch", "Kokosmilch"),
        ("Salz nach Geschmack", "Salz"),
        ("150 ml Frank's Hot Sauce", "Frank's Hot Sauce"),
        ("Klopapier", "Klopapier"),
        ("2 x Joghurt", "Joghurt"),
        ("1 Bund Frischer Koriander", "Koriander"),
        ("0,5 Kopf Eisbergsalat oder Butterlatich", "Eisbergsalat"),
        ("Butter / Margarine", "Butter"),
        ("500 g", "500 g"),
        ("Eier; Größe M", "Eier"),
        ("1 Stück Ingwer [frisch]", "Ingwer"),
    ]

    @Test("Suchbegriff wie shopSearchTerm()", arguments: cases)
    func term(_ input: String, _ expected: String) {
        #expect(Delivery.searchTerm(input) == expected)
    }

    @Test("Adressen wie shopSearchUrl()")
    func urls() {
        #expect(Delivery.searchURL(.rewe, name: "2 EL Crème fraîche")?.absoluteString == "https://www.rewe.de/shop/productList?search=Cr%C3%A8me%20fra%C3%AEche")
        #expect(Delivery.searchURL(.knuspr, name: "1 l Milch")?.absoluteString == "https://www.knuspr.de/suche?q=Milch")
    }
}
