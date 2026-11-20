import Foundation

public struct RecipeMarkdown {
    public struct Ingredient {
        public let name: String
        public let amount: String?
        public let group: String?

        public init(name: String, amount: String?, group: String?) {
            self.name = name
            self.amount = amount
            self.group = group
        }
    }

    public struct Metadata: Sendable {
        public enum Position: String, Sendable {
            case head, tail
        }

        public let key: String
        public let value: String
        public let position: Position

        public init(key: String, value: String, position: Position) {
            self.key = key
            self.value = value
            self.position = position
        }

    }

    public var title: String
    public var subtitle: String?
    public var source: String?
    public var cookbook: (title: String, page: Int?)?
    public var categories: [String] = []
    public var tags: [String] = []
    public var time: String?
    public var servings: Int?
    public var servingsText: String?
    public var ingredients: [Ingredient] = []
    public var steps: [String] = []
    public var tip: String?
    public var nutrition: String?
    public var metadata: [Metadata] = []

    public init(title: String) { self.title = title }

    public var text: String { block + "\n" }

    public static func collectionText(_ recipes: [Self]) -> String {
        let index = recipes.enumerated().map { offset, recipe in
            let anchor = recipe.title.lowercased()
                .replacingOccurrences(of: #"[^\p{L}\p{N} _-]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: " ", with: "-")
            return "\(offset + 1). [\(recipe.title)](#\(anchor))"
        }
        let heading = (["# Rezeptsammlung", "", "## Inhalt", ""] + index + ["", "---", "", ""]).joined(separator: "\n")
        return heading + recipes.map(\.block).joined(separator: "\n\n---\n\n") + "\n"
    }

    private var block: String {
        var head = [line("Untertitel", subtitle), line("Quelle", source)].compactMap { $0 }
        if let cookbook {
            let label = cookbook.page.map { "\(cookbook.title), S. \($0)" } ?? cookbook.title
            head.append("**Kochbuch:** \(label)  ")
        }
        if let category = line("Kategorie", categories.joined(separator: " / ")) { head.append(category) }
        if tags != categories.map(Self.slugifyTag) {
            head.append("**Tags:** \(tags.joined(separator: ", "))  ")
        }
        if let time = line("Zeit", time) { head.append(time) }
        if let servings {
            head.append("**Portionen:** \(servingsText ?? String(servings))  ")
        } else if let amount = line("Menge", servingsText) {
            head.append(amount)
        }
        head += metadata.filter { $0.position == .head }.map { "**\($0.key):** \($0.value)  " }

        var lines = ["## \(title)", ""] + head + ["", "### Zutaten", "", "| Zutat | Menge |", "|---|---|"]
        var group: String?
        for ingredient in ingredients {
            if let name = ingredient.group, !name.isEmpty, name != group { lines.append("| **\(name)** | |") }
            group = ingredient.group
            lines.append("| \(ingredient.name) | \(ingredient.amount ?? "") |")
        }

        lines += ["", "### Zubereitung", ""]
        lines += steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        let tail = [line("Tipp", tip), line("Nährwerte pro Portion", nutrition)].compactMap { $0 }
            + metadata.filter { $0.position == .tail }.map { "**\($0.key):** \($0.value)" }
        for entry in tail {
            lines += ["", entry.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)]
        }
        return lines.joined(separator: "\n")
    }

    private func line(_ label: String, _ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : "**\(label):** \($0)  " }
    }

    public static func slugifyTag(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}-]"#, with: "", options: .regularExpression)
    }
}

extension RecipeMarkdown {
    public enum ImportError: LocalizedError {
        case tooLarge, empty

        public var errorDescription: String? {
            switch self {
            case .tooLarge: "Die Datei ist zu groß."
            case .empty: "Kein Rezept im Markdown gefunden."
            }
        }
    }

    public static func parseCollection(_ text: String) throws -> [Self] {
        guard text.utf8.count <= 1_000_000 else { throw ImportError.tooLarge }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let separators = matches(#"\n-{3,}\s*\n"#, in: normalized)
        var start = normalized.startIndex
        var recipes: [Self] = []
        for end in separators.compactMap({ Range($0.range, in: normalized) }) + [normalized.endIndex..<normalized.endIndex] {
            if let recipe = parseBlock(String(normalized[start..<end.lowerBound])) {
                recipes.append(recipe)
            }
            start = end.upperBound
        }
        guard !recipes.isEmpty else { throw ImportError.empty }
        return recipes
    }

    public var timeMinutes: Int? {
        guard let time else { return nil }
        let values = Self.matches(#"(?i)([0-9]+(?:[.,][0-9]+)?)(?:\s*[–-]\s*([0-9]+(?:[.,][0-9]+)?))?\s*(Min|Std|h\b)"#, in: time)
        let minutes = values.reduce(0.0) { total, match in
            let value = Self.capture(match, 2, in: time) ?? Self.capture(match, 1, in: time) ?? ""
            let unit = Self.capture(match, 3, in: time) ?? ""
            return total + (Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0)
                * (unit.lowercased() == "min" ? 1 : 60)
        }
        return values.isEmpty ? nil : Int32(exactly: minutes.rounded()).map(Int.init)
    }

    public var diet: String {
        let categories = categories.map { $0.lowercased() }
        if categories.contains("fisch") { return "fisch" }
        if categories.contains(where: ["geflügel", "rind", "schwein", "fleisch", "lamm", "wild"].contains) { return "fleisch" }
        let names = ingredients.map {
            $0.name.lowercased().replacingOccurrences(of: #"\(.*?\)|gehackt\p{L}*"#, with: "", options: .regularExpression)
        }
        let meat = ["hähnchen", "huhn", "hühner", "chicken", "schwein", "rind", "hack", "schinken", "speck", "bacon", "salami", "wurst", "lamm", "pute", "ente", "kalb", "geflügel", "fleisch"]
        let fish = ["lachs", "garnele", "thunfisch", "fisch", "forelle", "kabeljau", "shrimp", "scampi", "dorade", "sardelle", "muschel"]
        if names.contains(where: { name in meat.contains(where: name.contains) }) { return "fleisch" }
        if names.contains(where: { name in fish.contains(where: name.contains) }) { return "fisch" }
        return "vegetarisch"
    }

    public var nutritionValues: [String: String]? {
        nutrition.flatMap(Self.parseNutrition)
    }

    public static func parseNutrition(_ input: String) -> [String: String]? {
        let nutrition = trim(input)
        guard !nutrition.isEmpty else { return nil }
        var values = ["text": nutrition]
        for part in nutrition.split(separator: "|").map({ Self.trim(String($0)) }) {
            if let match = Self.matches(#"(?i)^([0-9.,]+)\s*kcal$"#, in: part).first {
                values["kcal"] = Self.capture(match, 1, in: part)
            } else if let match = Self.matches(#"^(.+?)\s+([0-9.,]+\s*\S*)$"#, in: part).first,
                      let key = Self.capture(match, 1, in: part) {
                values[key] = Self.capture(match, 2, in: part)
            }
        }
        return values
    }

    private enum Section { case head, ingredients, steps, tail }

    private static func parseBlock(_ block: String) -> Self? {
        let lines = block.components(separatedBy: "\n")
        guard let heading = lines.first(where: { $0.range(of: #"^##\s+"#, options: .regularExpression) != nil }) else { return nil }
        let title = trim(heading.replacingOccurrences(of: #"^##\s+"#, with: "", options: .regularExpression))
        guard !title.isEmpty else { return nil }
        if title == "Inhalt", !block.contains("### Zutaten") { return nil }

        var recipe = Self(title: title)
        var section = Section.head
        var metadata: [Metadata] = []
        var group: String?
        for raw in lines {
            let line = raw.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            if line.range(of: #"^##\s+"#, options: .regularExpression) != nil { continue }
            if line.range(of: #"(?i)^###\s+Zutaten"#, options: .regularExpression) != nil {
                section = .ingredients
                continue
            }
            if line.range(of: #"(?i)^###\s+Zubereitung"#, options: .regularExpression) != nil {
                section = .steps
                continue
            }
            if section != .ingredients, let match = matches(#"^\*\*(.+?):\*\*\s*(.*)$"#, in: line).first,
               let key = capture(match, 1, in: line), let value = capture(match, 2, in: line) {
                metadata.append(.init(key: trim(key), value: trim(value), position: section == .head ? .head : .tail))
                if section == .steps { section = .tail }
            } else if section == .ingredients, line.hasPrefix("|") {
                let content = line.hasSuffix("|") ? line.dropFirst().dropLast() : line.dropFirst()
                let cells = content.split(separator: "|", omittingEmptySubsequences: false).map { trim(String($0)) }
                guard cells.count >= 2 else { continue }
                let name = cells[0]
                let amount = cells[1]
                if name == "Zutat" && amount == "Menge" { continue }
                if name.replacingOccurrences(of: ":", with: "").range(of: #"^-+$"#, options: .regularExpression) != nil { continue }
                if amount.isEmpty, name.hasPrefix("**"), name.hasSuffix("**"), name.count > 4 {
                    group = trim(String(name.dropFirst(2).dropLast(2)))
                } else {
                    recipe.ingredients.append(.init(name: name, amount: amount.isEmpty ? nil : amount, group: group))
                }
            } else if section == .steps, let match = matches(#"^[0-9]+\.\s+(.*)$"#, in: line).first,
                      let step = capture(match, 1, in: line) {
                recipe.steps.append(trim(step))
            }
        }
        recipe.apply(metadata)
        return recipe
    }

    private mutating func apply(_ entries: [Metadata]) {
        func value(_ key: String) -> String? { entries.first { $0.key == key }?.value }
        subtitle = value("Untertitel")
        source = value("Quelle")
        if let book = value("Kochbuch"), !book.isEmpty {
            if let match = Self.matches(#"^(.*?),\s*S\.\s*([0-9]+)\s*$"#, in: book).first,
               let title = Self.capture(match, 1, in: book) {
                cookbook = (Self.trim(title), Self.capture(match, 2, in: book).flatMap(Int32.init).map(Int.init))
            } else {
                cookbook = (book, nil)
            }
        }
        categories = (value("Kategorie") ?? "").components(separatedBy: " / ").map(Self.trim).filter { !$0.isEmpty }
        let tagLine = value("Tags") ?? ""
        tags = (tagLine.isEmpty ? categories : tagLine.components(separatedBy: ",")).map(Self.slugifyTag).filter { !$0.isEmpty }
        time = value("Zeit")
        if let portions = value("Portionen"), let range = portions.range(of: #"[0-9]+"#, options: .regularExpression) {
            servings = Int32(portions[range]).map(Int.init)
        }
        servingsText = value("Portionen") ?? value("Menge")
        tip = value("Tipp")
        nutrition = value("Nährwerte pro Portion")
        let head = ["Untertitel", "Quelle", "Kochbuch", "Kategorie", "Zeit", "Portionen", "Menge", "Tags"]
        let tail = ["Tipp", "Nährwerte pro Portion"]
        metadata = entries.filter { !($0.position == .head ? head : tail).contains($0.key) }
    }

    private static func trim(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        Range(match.range(at: index), in: text).map { String(text[$0]) }
    }
}
