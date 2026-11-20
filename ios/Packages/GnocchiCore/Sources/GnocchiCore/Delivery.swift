import Foundation

/// Lieferdienste ohne Partner-Schnittstelle: Jeder offene Posten öffnet die Produktsuche des Shops.
/// Gegenstück zu `lib/delivery.ts` – Verhalten muss gleich bleiben (ParityTests).
public enum Delivery {
    public enum Shop: String, CaseIterable, Sendable {
        case rewe, knuspr

        public var name: String { self == .rewe ? "REWE" : "Knuspr" }

        public var home: URL {
            URL(string: self == .rewe ? "https://www.rewe.de/shop/" : "https://www.knuspr.de/")!
        }

        public func search(_ query: String) -> URL? {
            guard let q = Delivery.encodeComponent(query) else { return nil }
            switch self {
            case .rewe: return URL(string: "https://www.rewe.de/shop/productList?search=" + q)
            case .knuspr: return URL(string: "https://www.knuspr.de/suche?q=" + q)
            }
        }
    }

    private static let units = [
        "kg", "g", "mg", "l", "ml", "cl", "dl", "el", "tl", "msp", "prise", "prisen", "stk", "stück", "st",
        "bund", "dose", "dosen", "packung", "packungen", "pck", "pkg", "päckchen", "becher", "glas", "gläser",
        "flasche", "flaschen", "beutel", "zehe", "zehen", "scheibe", "scheiben", "tasse", "tassen", "handvoll",
        "würfel", "stange", "stangen", "kopf", "köpfe", "netz", "schale", "schalen", "tube", "tuben",
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let parens = regex(#"\([^)]*\)"#)
    private static let brackets = regex(#"\[[^\]]*\]"#)
    private static let separator = regex(#",(?!\d)|;"#)
    private static let spaces = regex(#"\s+"#)
    private static let quantity = regex(#"^(?:ca\.?\s*|etwa\s+)?(?:\d+(?:[.,]\d+)?|\d+/\d+|[½¼¾⅓⅔])(?:\s*(?:-|–|bis)\s*(?:\d+(?:[.,]\d+)?|[½¼¾]))?\s*(?:x\s+)?"#)
    private static let unit = regex("^(?:" + units.joined(separator: "|") + #")\.?(?=\s|$)"#)
    private static let filler = regex(#"^(?:x\s+|von\s+|à\s+)"#)
    private static let adjectives = regex(#"^(?:groß|klein|mittelgroß|frisch|reif|getrocknet|gehackt)(?:e[mnrs]?)?\s+"#)
    private static let alternatives = regex(#"\s+oder\s+|\s+/\s+"#)
    private static let suffix = regex(#"\s+(?:nach Geschmack|zum Servieren|optional|n\. B\.|nach Belieben)$"#)

    private static func replace(_ re: NSRegularExpression, in s: String, with template: String = "") -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Suchbegriff aus einem Listenposten: ohne Menge, Einheit, Klammern und Zusatz nach dem Komma.
    /// "480 g Hähnchenschenkel (ohne Knochen/Haut)" → "Hähnchenschenkel"
    public static func searchTerm(_ name: String) -> String {
        var s = name.precomposedStringWithCanonicalMapping
        s = replace(parens, in: s, with: " ")
        s = replace(brackets, in: s, with: " ")
        if let m = separator.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range, in: s) {
            s = String(s[..<r.lowerBound])
        }
        if let m = alternatives.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range, in: s) {
            s = String(s[..<r.lowerBound])
        }
        s = replace(spaces, in: s, with: " ").trimmingCharacters(in: .whitespaces)
        for _ in 0..<3 {
            let before = s
            s = replace(quantity, in: s)
            s = replace(unit, in: s)
            s = replace(filler, in: s).trimmingCharacters(in: .whitespaces)
            if s == before { break }
        }
        s = replace(adjectives, in: s)
        s = replace(suffix, in: s).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? name.trimmingCharacters(in: .whitespaces) : s
    }

    public static func searchURL(_ shop: Shop, name: String) -> URL? {
        shop.search(searchTerm(name))
    }

    /// Wie encodeURIComponent in JavaScript.
    static func encodeComponent(_ s: String) -> String? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
