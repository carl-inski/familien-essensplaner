import Foundation

extension Quantity {
    // Dieselben Einheiten und Rundungsregeln wie parseAmount in lib/quantity.ts.
    private static let aliases: [String: String] = [
        "g": "g", "gramm": "g", "kg": "kg", "ml": "ml", "l": "l",
        "liter": "l", "el": "EL", "tl": "TL", "stück": "Stück", "stk": "Stück",
        "stk.": "Stück", "bund": "Bund", "dose": "Dose", "dosen": "Dose", "pck.": "Pck.",
        "pck": "Pck.", "packung": "Pck.", "packungen": "Pck.", "päckchen": "Pck.", "zehe": "Zehen",
        "zehen": "Zehen", "kugel": "Kugeln", "kugeln": "Kugeln", "kopf": "Kopf", "handvoll": "Handvoll",
        "scheibe": "Scheiben", "scheiben": "Scheiben", "prise": "Prise", "prisen": "Prise", "schuss": "Schuss",
        "cm": "cm", "becher": "Becher", "glas": "Glas", "tasse": "Tasse", "tassen": "Tasse",
        "esslöffel": "EL", "essl.": "EL", "teelöffel": "TL", "teel.": "TL", "msp": "Msp.",
        "msp.": "Msp.", "messerspitze": "Msp.", "tbsp": "EL", "tbs": "EL", "tablespoon": "EL",
        "tablespoons": "EL", "tsp": "TL", "teaspoon": "TL", "teaspoons": "TL", "cup": "cup",
        "cups": "cup", "oz": "oz", "ounce": "oz", "ounces": "oz", "lb": "lb",
        "lbs": "lb", "pound": "lb", "pounds": "lb", "pint": "pint", "pints": "pint",
        "quart": "quart", "quarts": "quart"
    ]

    private static let numberToken = #"[0-9]+/[0-9]+|[0-9]+(?:[.,][0-9]+)?[½¼¾⅓⅔⅛]?|[½¼¾⅓⅔⅛]"#
    private static let rangeSeparator = #"(?:\s*[–-]\s*|\s+(?:bis|to)\s+)"#

    public static func splitIngredientLine(_ line: String) -> (amount: String?, name: String) {
        let cleaned = line.replacing(pattern: #"\s+"#, with: " ").trimmed
        if let prefix = cleaned.range(of: #"^etwas "#, options: [.regularExpression, .caseInsensitive]) {
            return (String(cleaned[prefix]).trimmed, String(cleaned[prefix.upperBound...]))
        }
        let text = cleaned.replacing(pattern: #"^(?:ca\.|\b(?:etwa|circa)\b)\s*"#, with: "", ignoreCase: true)
        let number = "(?:" + numberToken + ")"
        let pattern = "^(" + number + "(?:" + rangeSeparator + number + #")?)\s*(?:([A-Za-zÄÖÜäöüß]+\.?)(?=\s|$))?\s*(.*)$"#
        guard let match = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive).firstMatch(
            in: text, range: NSRange(text.startIndex..., in: text)
        ) else { return (nil, text) }
        func capture(_ index: Int) -> String {
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
        let word = capture(2)
        let rest = capture(3)
        if aliases[word.lowercased()] != nil {
            let name = rest.replacing(pattern: #"^[,:]\s*"#, with: "").trimmed
            return (capture(1) + " " + word, name.isEmpty ? text : name)
        }
        let name = (word + " " + rest).trimmed
        return name.isEmpty ? (nil, text) : (capture(1), name)
    }

    public static func parseAmount(_ text: String) -> Self? {
        let token = "(" + numberToken + ")"
        let pattern = "^" + token + "(?:" + rangeSeparator + token + #")?\s*([A-Za-zÄÖÜäöüß.]+)?"#
        let input = text.trimmed
        guard let match = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive).firstMatch(
            in: input, range: NSRange(input.startIndex..., in: input)
        ) else { return nil }
        func capture(_ index: Int) -> String? {
            Range(match.range(at: index), in: input).map { String(input[$0]) }
        }
        guard let value = capture(2) ?? capture(1), let amount = parseNumber(value) else { return nil }
        let unit = capture(3).flatMap { aliases[$0.lowercased()] }
        let conversion: (Double, String)? = switch unit {
        case "cup": (240, "ml")
        case "oz": (28.35, "g")
        case "lb": (453.6, "g")
        case "pint": (473, "ml")
        case "quart": (946, "ml")
        default: nil
        }
        guard let (scale, target) = conversion else { return Self(amount: amount, unit: unit) }
        let metric = amount * scale
        let rounded = metric < 100 ? max(5, (metric / 5).rounded() * 5) : (metric / 10).rounded() * 10
        return Self(amount: rounded, unit: target)
    }

    private static func parseNumber(_ token: String) -> Double? {
        let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1 / 3, "⅔": 2 / 3, "⅛": 0.125]
        if let last = token.last, let fraction = fractions[last] {
            if token.count == 1 { return fraction }
            return Double(token.dropLast()).map { $0 + fraction }
        }
        if let separator = token.firstIndex(of: "/"),
           let numerator = Double(token[..<separator]), let denominator = Double(token[token.index(after: separator)...]),
           denominator != 0 {
            return numerator / denominator
        }
        return Double(token.replacingOccurrences(of: ",", with: ".")).flatMap { $0.isFinite ? $0 : nil }
    }
}
