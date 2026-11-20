import Foundation

public enum IngredientName {
    public static func display(_ name: String) -> String {
        let clean = name.replacing(pattern: #"\s*\((?:optional|zum |für |als |nach )[^)]*\)"#, with: "", ignoreCase: true)
            .replacing(pattern: #"\s+"#, with: " ").trimmed
        return clean.isEmpty ? name : clean
    }

    public static func shoppingKey(_ name: String) -> String {
        let lower = display(name).lowercased()
        let variants = [
            (#"\b(?:tk|tiefgekühlt\w*)\b"#, "tk"),
            ("getrocknet", "trocken"),
            ("gemahlen", "gemahlen"),
            (#"\b(?:dose|konserve)\b"#, "dose")
        ].compactMap { lower.matches(pattern: $0.0) ? $0.1 : nil }

        var core = lower.replacing(pattern: #"\([^)]*\)"#, with: " ")
            .components(separatedBy: ",")[0].replacing(pattern: #"\s+"#, with: " ").trimmed
        while true {
            let stripped = core.replacing(pattern: #"^(?:frisch|gehackt|gerieben|geschält|gewürfelt|fein|grob|klein)(?:e[nrs]?)?\s+"#, with: "")
            if stripped == core { break }
            core = stripped
        }
        core = core.replacing(pattern: #"^tk\b-?\s*"#, with: "")
            .replacing(pattern: #"\b(?:getrocknet|gemahlen)(?:e[nrs]?)?\s+"#, with: "")
            .replacing(pattern: #"[-\s]+"#, with: "")
        let stem = self.stem(core)
        return ([stem.isEmpty ? lower : stem] + variants).joined(separator: "+")
    }

    static func stem(_ word: String) -> String {
        let stem = word.replacing(pattern: "(?:ern|er|en|n|e|s)$", with: "")
        return stem.isEmpty ? word : stem
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    func replacing(pattern: String, with replacement: String, ignoreCase: Bool = false) -> String {
        replacingOccurrences(of: pattern, with: replacement,
                             options: ignoreCase ? [.regularExpression, .caseInsensitive] : .regularExpression)
    }

    func matches(pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
