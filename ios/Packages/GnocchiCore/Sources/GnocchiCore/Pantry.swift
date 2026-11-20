import Foundation

public enum Pantry {
    public static func entriesCovering(_ name: String, in pantry: Set<String>) -> Set<String> {
        let groups = groups(in: name)
        let whole = groups.map(joinAlternatives).joined(separator: ", ")
        var entries: Set<String> = pantry.contains(whole) ? [whole] : []
        for group in groups {
            let key = joinAlternatives(group)
            if pantry.contains(key) { entries.insert(key) }
            for alternative in group {
                entries.formUnion(pantry.filter { matches(alternative, entry: $0) })
            }
        }
        return entries
    }

    public static func entriesToAdd(_ name: String) -> Set<String> {
        Set(groups(in: name).map(joinAlternatives))
    }

    public static func entriesFromInput(_ text: String) -> Set<String> {
        Set(text.components(separatedBy: CharacterSet(charactersIn: ",;").union(.newlines)).compactMap { entry in
            let key = groups(in: entry).map(joinAlternatives).joined(separator: ", ")
            return isValid(key) ? key : nil
        })
    }

    public static func isValid(_ entry: String) -> Bool {
        !entry.trimmed.isEmpty && !entry.hasPrefix("-") && !entry.hasSuffix("-")
    }

    public static func remaining(_ name: String, in pantry: Set<String>) -> String? {
        guard !pantry.isEmpty else { return name }
        let groups = groups(in: name)
        guard !groups.isEmpty else { return name }
        guard !pantry.contains(groups.map(joinAlternatives).joined(separator: ", ")) else { return nil }
        let rest = groups.filter { group in
            !pantry.contains(joinAlternatives(group)) && !group.contains { alternative in
                pantry.contains { matches(alternative, entry: $0) }
            }
        }
        if rest.isEmpty { return nil }
        if rest.count == groups.count { return name }
        let text = rest.map(joinAlternatives).joined(separator: ", ")
        return text.prefix(1).uppercased() + String(text.dropFirst())
    }

    private static func joinAlternatives(_ group: [String]) -> String {
        group.joined(separator: " oder ")
    }

    private static func matches(_ alternative: String, entry key: String) -> Bool {
        guard isValid(key) else { return false }
        let stem = IngredientName.stem(alternative)
        let lastWord = alternative.split(separator: " ").last.map(String.init) ?? alternative
        let keyStem = IngredientName.stem(key)
        return key == alternative || keyStem == stem
            || (!key.contains(" ") && (key == lastWord || keyStem == IngredientName.stem(lastWord)))
    }

    private static func groups(in name: String) -> [[String]] {
        let base = IngredientName.display(name).replacing(pattern: #"\(.*?\)"#, with: " ")
            .replacing(pattern: #"\s+"#, with: " ").trimmed
        var items: [String] = []
        for chunk in base.components(separatedBy: ",").map(\.trimmed) where !chunk.isEmpty {
            if !items.isEmpty && !chunk.matches(pattern: #"(^|\s)\p{Lu}"#) { continue }
            items.append(contentsOf: splitWords(chunk, separator: #"\s+(?:und|&|\+)\s+"#))
        }
        return items.map { item in
            splitWords(item, separator: #"\s+oder\s+"#).flatMap { text in
                text.matches(pattern: #"[^\s]/[^\s]"#) ? [text] : text.components(separatedBy: "/")
            }.map { $0.trimmed.lowercased() }.filter { !$0.isEmpty }
        }.filter { !$0.isEmpty }
    }

    private static func splitWords(_ text: String, separator: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: separator) else { return [text] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
        var result: [String] = []
        var start = text.startIndex
        for (index, match) in matches.enumerated() {
            let current = text[start..<match.lowerBound]
            let nextEnd = index + 1 < matches.count ? matches[index + 1].lowerBound : text.endIndex
            let next = text[match.upperBound..<nextEnd]
            if current.hasSuffix("-") || next.hasPrefix("-") { continue }
            result.append(String(current).trimmed)
            start = match.upperBound
        }
        result.append(String(text[start...]).trimmed)
        return result.filter { !$0.isEmpty }
    }
}
