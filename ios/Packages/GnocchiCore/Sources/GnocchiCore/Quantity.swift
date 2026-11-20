import Foundation

public struct Quantity: Equatable, Sendable {
    public let amount: Double
    public let unit: String?

    private static let pieces: Set<String?> = [
        nil, "Stück", "Kugeln", "Zehen", "Dose", "Pck.", "Bund", "Kopf", "Glas", "Becher", "Scheiben"
    ]
    private static let imperial: Set<String> = [
        "cup", "cups", "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "pint", "pints", "quart", "quarts"
    ]

    public init(amount: Double, unit: String?) {
        self.amount = amount
        self.unit = unit
    }

    public func scaled(by factor: Double) -> Self {
        var value = amount * factor
        var unit = unit
        if unit == "kg" || unit == "l" {
            value *= 1_000
            unit = unit == "kg" ? "g" : "ml"
        }
        if unit == "g" || unit == "ml" {
            value = Self.round(value, step: value < 100 ? 5 : 10)
            if value == 0 && amount > 0 { value = 5 }
        } else if Self.pieces.contains(unit) {
            value = value < 1 ? ceil(value * 2 - 1e-9) / 2 : ceil(value - 1e-9)
        } else {
            value = max(0.5, Self.round(value, step: 0.5))
        }
        return Self(amount: (value * 1_000).rounded() / 1_000, unit: unit)
    }

    public var formatted: String {
        let displayed: Self = switch (unit, amount) {
        case ("g", 1_000...): Self(amount: amount / 1_000, unit: "kg")
        case ("ml", 1_000...): Self(amount: amount / 1_000, unit: "l")
        default: self
        }
        let number = displayed.amount.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "de_DE")))
        return [number, displayed.unit].compactMap { $0 }.joined(separator: " ")
    }

    public func displayText(originalText: String?, original: Self) -> String {
        guard let originalText, !originalText.isEmpty else { return originalText ?? "" }
        let afterNumber = originalText.replacingOccurrences(
            of: #"^[\d.,/½¼¾⅓⅔⅛]+(\s*[–-]\s*[\d.,/½¼¾⅓⅔⅛]+)?\s*"#, with: "", options: .regularExpression
        )
        let word = afterNumber.prefix { $0.isLetter || $0 == "." }
        let isImperial = Self.imperial.contains(word.lowercased())
        if self == original && !isImperial { return originalText }
        let suffix = unit == nil && !isImperial ? afterNumber[...] : afterNumber.dropFirst(word.count)
        return [formatted, suffix.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func round(_ value: Double, step: Double) -> Double {
        floor(value / step + 0.5) * step
    }
}
