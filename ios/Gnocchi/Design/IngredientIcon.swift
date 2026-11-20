import GnocchiCore
import SwiftUI
import UIKit

struct IngredientIcon: View {
    let name: String
    let aisle: String?
    @ScaledMetric(relativeTo: .title2) private var iconSize = 27.0

    @ViewBuilder var body: some View {
        if let generatedImage {
            Image(uiImage: generatedImage)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
        } else if let asset = illustration {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
        } else {
            Text(emoji(matching: matches)).font(.title2)
        }
    }

    private var illustration: String? { Self.illustration(for: name) }

    private var generatedImage: UIImage? {
        IngredientEmojiCatalog.generatedKey(for: name).flatMap(IngredientEmojiImages.image(for:))
    }

    nonisolated static func illustration(for name: String) -> String? {
        let words = (IngredientEmojiCatalog.alternatives(in: name).first ?? name).lowercased().split { !$0.isLetter }
        let phrase = " \(words.joined(separator: " ")) "
        return illustrations.first { matches($0.terms, words: words, phrase: phrase) }.map { "ingredient-\($0.asset)" }
    }

    private func matches(_ terms: [String]) -> Bool {
        let words = (IngredientEmojiCatalog.alternatives(in: name).first ?? name).lowercased().split { !$0.isLetter }
        return Self.matches(terms, words: words, phrase: " \(words.joined(separator: " ")) ")
    }

    private nonisolated static func matches(_ terms: [String], words: [Substring], phrase: String) -> Bool {
        terms.contains { term in
            term.count > 2 ? phrase.contains(term) : words.contains(Substring(term))
        }
    }

    func inlineText(size: CGFloat) -> Text {
        guard let image = generatedImage ?? illustration.flatMap(UIImage.init(named:)) else {
            return Text(emoji(matching: matches))
        }
        let fitted = min(size / image.size.width, size / image.size.height)
        let width = image.size.width * fitted
        let height = image.size.height * fitted
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            image.draw(in: CGRect(x: (size - width) / 2, y: (size - height) / 2,
                                  width: width, height: height))
        }
        return Text(Image(uiImage: rendered))
    }

    var hasCatalogIcon: Bool { illustration != nil || IngredientEmojiCatalog.emoji(for: name) != nil }

    private func emoji(matching matches: ([String]) -> Bool) -> String {
        if let emoji = IngredientEmojiCatalog.emoji(for: name) { return emoji }
        if let icon = Self.icons.first(where: { entry in
            matches(entry.terms)
        }) {
            return icon.emoji
        }
        switch aisle ?? Aisles.forIngredient(name) {
        case "Obst & Gemüse": return "🥬"
        case "Kühlregal": return "🥛"
        case "Frischetheke": return "🍖"
        case "Trockenware": return "🫙"
        case "Gewürze": return "🧂"
        case "Tiefkühl": return "🧊"
        case "Getränke": return "🥤"
        default: return "🥣"
        }
    }

    private nonisolated static let illustrations: [(asset: String, terms: [String])] = [
        ("rolled-oats", ["haferflock", "rolled oats", "porridge oats"]),
        ("kidney-beans", ["kidneybohn", "kidney bohn", "rote bohnen", "kidney beans"]),
        ("red-lentils", ["rote linse", "roten linsen", "red lentil"]),
        ("chickpeas", ["kichererbs", "chickpea", "garbanzo"]),
        ("pesto", ["pesto"]),
        ("breadcrumbs", ["panko", "paniermehl", "semmelbrösel", "semmel brösel", "breadcrumbs"]),
        ("lasagna-sheets", ["lasagneplatt", "lasagne platt", "lasagna sheets", "lasagneblätt"]),
        ("ketchup", ["ketchup", "catsup"]),
        ("halloumi", ["halloumi", "grillkäse"]),
        ("greek-yogurt", ["joghurt", "jogurt", "yogurt", "yoghurt"]),
        ("harissa", ["harissa", "harisa"]),
        ("maple-syrup", ["ahornsirup", "ahorn sirup", "maple syrup"]),
        ("bouillon", ["brühwürfel", "brühewürfel", "brühe würfel", "bouillonwürfel", "suppenwürfel"]),
        ("pine-nuts", ["pinienkern", "pine nuts"]),
        ("pecans", ["pekann", "pekan n", "pecan"]),
        ("balsamic-glaze", ["balsamicocreme", "balsamico creme", "balsamic glaze"]),
        ("smoked-salmon", ["räucherlachs", "räucher lachs", "smoked salmon"]),
        ("feta", ["feta", "schafskäse"]),
        ("mozzarella", ["mozzarella"]),
        ("parmesan", ["parmesan", "parmigiano", "grana padano"]),
        ("cottage-cheese", ["hüttenkäse", "körniger frischkäse", "cottage cheese"]),
        ("garlic-powder", ["knoblauchpulver", "knoblauch pulver", "knoblauchgranul", "knoblauch granul"]),
        ("olive-oil", ["olivenöl", "oliven öl"]),
        ("coconut-milk", ["kokosmilch", "kokos milch"]),
        ("teriyaki", ["teriyaki"]),
        ("mustard", ["senf ", "mustard"]),
        ("mayonnaise", ["mayonnaise", "mayonaise", " mayo "]),
        ("ranch", [" ranch ", "ranchdressing"]),
        ("cashew", ["cashew", "kaschukern"]),
        ("nutmeg", ["muskat", "nutmeg"]),
        ("bay-leaf", ["lorbeer", "bay leaf"]),
        ("fusilli", ["fusilli", "spiralnudel"]),
        ("gnocchi", ["gnocchi"]),
        ("burrata", ["burrata", "burratina"]),
        ("tofu", ["tofu"]),
        ("shimeji", ["shimeji", "buchenpilz"]),
        ("wakame", ["wakame", "meeresalgen"]),
        ("spring-onion", ["frühlingszwiebel", "lauchzwiebel", "schlotten"]),
        ("sesame", ["sesamsamen", "sesamkörn", " sesam "]),
        ("miso", ["miso"]),
        ("soy-sauce", ["sojasauce", "sojasoße", "soja sauce", "soja soße", "tamari"]),
        ("rice-paper", ["reispapier", "reis papier", "rice paper"]),
        ("rice-noodles", ["reisnudel", "reisbandnudel", "reis nudel", "reis vermicelli", "rice noodle", "rice vermicelli"]),
        ("sprouts", [" sprosse ", "sprossen", "keimling"]),
        ("asparagus", ["spargel"]),
        ("capers", ["kapern"]),
        ("tomato-paste", ["tomatenmark", "tomaten mark"]),
        ("shortcrust", ["mürbeteig", "mürbe teig"]),
        ("potato-dumpling", ["kloßteig", "klossteig", "knödelteig", "kartoffelknödel", "kartoffelklöße"]),
        ("tortilla", ["tortilla", "wraps"]),
        ("sugar", ["zucker ", "zuckerrohrsaft"]),
        ("yeast", ["hefe"]),
        ("cinnamon", ["zimt"]),
        ("cumin", ["kreuzkümmel", " cumin "]),
        ("curry-paste", ["currypaste", "curry paste"]),
        ("mirin", ["mirin"]),
        ("creme-fraiche", ["crème fraîche", "creme fraiche", "schmand", "saure sahne", "sauerrahm"]),
        ("guacamole", ["guacamole"]),
        ("jam", ["marmelade", "konfitüre", "fruchtaufstrich"]),
        ("peanut-butter", ["erdnussbutter", "erdnussmus"]),
        ("balsamic", ["balsamico", "balsamessig"]),
        ("ground-spice", ["paprikapulver", "paprika edelsüß", "räucherpaprika", "chilipulver", "cajun gewürz"]),
        ("frozen-berries", ["tk beeren", "beerenmischung", "beerenmix"]),
        ("stock", ["brühe", "fond ", "dashi"])
    ]

    private static let icons: [(emoji: String, terms: [String])] = [
        ("🥥", ["kokos"]), ("🍅", ["tomat"]), ("🫒", ["olive"]),
        ("🧄", ["knoblauch"]), ("🧅", ["zwiebel", "schalotte"]), ("🫚", ["ingwer"]),
        ("🍄‍🟫", ["pilz", "champignon", "shiitake", "shimeji"]),
        ("🥔", ["kartoffel"]), ("🫛", ["erbs"]), ("🥕", ["karotte", "möhre"]), ("🥦", ["brokkoli", "broccoli"]),
        ("🌶️", ["chili", "peperoni", "cayenne"]), ("🫑", ["paprika"]),
        ("🥬", ["salat", "latich", "romana", "spinat", "kohl", "rucola", "wakame", "algen"]),
        ("🥒", ["gurke", "zucchini"]), ("🍆", ["aubergine"]), ("🥑", ["avocado"]), ("🌽", ["mais"]),
        ("🌿", ["basilikum", "petersilie", "koriander", "schnittlauch", "minze", "thymian", "oregano", "rosmarin", "dill"]),
        ("🍋", ["zitrone"]), ("🍋‍🟩", ["limette"]), ("🍊", ["orange", "mandarine"]),
        ("🍎", ["apfel", "äpfel"]), ("🍓", ["erdbeer"]), ("🫐", ["blaubeer", "heidelbeer"]),
        ("🍌", ["banane"]), ("🍍", ["ananas"]), ("🥭", ["mango"]),
        ("🍚", ["reis", "basmati"]), ("🍝", ["nudel", "pasta", "spaghetti", "gnocchi", "penne", "lasagne", "orzo"]),
        ("🍞", ["brot", "toast", "brötchen"]), ("🌾", ["mehl", "hafer", "bulgur", "couscous"]),
        ("🫘", ["bohne", "linse", "kichererbse", "tofu", "edamame"]), ("🥜", ["nuss", "mandel", "cashew", "pistazie"]),
        ("🧀", ["käse", "mozzarella", "burrata", "feta", "parmesan", "ricotta", "pecorino"]),
        ("🧈", ["butter"]), ("🥚", ["ei", "eier", "eigelb", "eiweiß"]),
        ("🥛", ["milch", "sahne", "rahm", "joghurt", "quark", "schmand"]),
        ("🍗", ["hähnchen", "huhn", "poulet", "pute"]), ("🥓", ["speck", "schinken", "bacon"]),
        ("🥩", ["rind", "schwein", "hackfleisch", "steak", "lamm"]),
        ("🐟", ["lachs", "fisch", "thunfisch", "forelle"]), ("🦐", ["garnele", "shrimp", "crevette", "scampi"]),
        ("🍯", ["honig", "sirup"]), ("🍫", ["schokolade", "kakao"]),
        ("🧂", ["salz", "pfeffer"]), ("🫙", ["öl", "essig", "sauce", "soße", "miso", "senf", "sesam"]),
        ("🍶", ["sake"]), ("🍷", ["wein", "sherry"]), ("💧", ["wasser"])
    ]
}

enum IngredientEmojiCatalog {
    struct Term: Identifiable, Hashable {
        let name: String
        let emoji: String
        let searchKey: String
        var id: String { name }
        var illustration: String? { IngredientEmojiCatalog.illustrationsByName[name] }
        var hasGeneratedImage: Bool { IngredientEmojiCatalog.generatedKeys.contains(searchKey) }
    }

    static let terms: [Term] = {
        guard let url = Bundle.main.url(forResource: "ingredient-emojis", withExtension: "txt"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [Term] = []
        var names: Set<String> = []
        for line in source.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t", maxSplits: 1)
            guard columns.count == 2 else { continue }
            let emoji = String(columns[0])
            for value in columns[1].split(separator: "|") {
                let name = String(value)
                guard names.insert(name).inserted else { continue }
                result.append(Term(name: name, emoji: emoji, searchKey: key(name)))
            }
        }
        return result
    }()

    static let entries = Dictionary(terms.map { ($0.searchKey, $0.emoji) }, uniquingKeysWith: { _, last in last })

    private static let illustrationsByName = Dictionary(uniqueKeysWithValues: terms.compactMap { term in
        IngredientIcon.illustration(for: term.name).map { (term.name, $0) }
    })

    private static let locale = Locale(identifier: "de_DE")

    private static let generatedKeys: Set<String> = {
        guard let folder = Bundle.main.resourceURL?.appending(path: "IngredientEmojis", directoryHint: .isDirectory),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return Set(files.filter { $0.pathExtension == "png" }.map { $0.deletingPathExtension().lastPathComponent })
    }()

    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            .replacingOccurrences(of: "ß", with: "ss")
            .filter { $0.isLetter || $0.isNumber }
    }

    static func alternatives(in name: String) -> [String] {
        let withoutNotes = name.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        return withoutNotes.replacingOccurrences(of: #"(?i)\s+(?:oder|alternativ)\s+|\s*/\s*"#,
                                                with: "|", options: .regularExpression)
            .split(separator: "|")
            .map { $0.components(separatedBy: ",")[0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func emoji(for name: String) -> String? {
        matchingKeys(for: name).lazy.compactMap { entries[$0] }.first
    }

    static func generatedKey(for name: String) -> String? {
        matchingKeys(for: name).first(where: generatedKeys.contains)
    }

    private static func matchingKeys(for name: String) -> [String] {
        guard let first = alternatives(in: name).first else { return [] }
        let base = first.replacingOccurrences(
            of: #"(?i)^(?:(?:frisch|gehackt|gerieben|gemahlen|getrocknet|geschält|gewürfelt|gekocht|tiefgekühlt|ungesalzen|flüssig|trocken|reif|fein|grob)(?:e[nrsm]?)?\s+|(?:bio|tk)[\s-]+)+"#,
            with: "", options: .regularExpression
        )
        let trimmed = base.replacingOccurrences(
            of: #"(?i)\s+(?:zum|zur|mit haut|ohne haut|in verschiedenen farben)\b.*$"#,
            with: "", options: .regularExpression
        )
        var candidates: [String] = []
        for value in [key(first), key(base), key(trimmed)] where !value.isEmpty && !candidates.contains(value) {
            candidates.append(value)
            if value.hasSuffix("blatter") { candidates.append(String(value.dropLast(2))) }
            for ending in ["en", "ern", "er", "n", "e", "s"] where value.count >= ending.count + 2 && value.hasSuffix(ending) {
                candidates.append(String(value.dropLast(ending.count)))
            }
        }
        return candidates
    }

    static func missingNames(in names: [String]) -> [String] {
        names.flatMap { name in
            let parts = alternatives(in: name)
            return parts.enumerated().compactMap { index, part -> String? in
                if emoji(for: part) != nil || IngredientIcon.illustration(for: part) != nil { return nil }
                if index > 0, part.hasPrefix("-"), let first = parts.first, expands(part, from: first) { return nil }
                return part
            }
        }
    }

    private static func expands(_ abbreviation: String, from first: String) -> Bool {
        let suffix = key(abbreviation)
        let full = key(first)
        guard suffix.count >= 3 else { return false }
        return entries.keys.contains { candidate in
            guard candidate.hasSuffix(suffix), candidate.count >= suffix.count + 4 else { return false }
            return full.hasPrefix(candidate.dropLast(suffix.count))
        }
    }
}

@MainActor
enum IngredientEmojiImages {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 240
        return cache
    }()

    static func image(for key: String) -> UIImage? {
        if let image = cache.object(forKey: key as NSString) { return image }
        guard let url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "IngredientEmojis"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}

struct IngredientMentions {
    struct Match {
        let range: Range<String.Index>
        let ingredient: Recipe.Ingredient
        let iconName: String
    }

    private struct Name {
        let text: String
        let iconName: String
        let ingredient: Recipe.Ingredient
    }

    private struct Term {
        let regex: NSRegularExpression
        let name: Name
    }

    private let terms: [Term]

    private static let ricePaperNames = ["Reispapier", "Reispapierblatt", "Reispapierblätter", "rice paper"]
    private static let endings = ["es", "en", "er", "e", "s", "n"]

    // Short names only apply when the recipe contains a matching ingredient.
    // The spelling in the step is retained so, for example, "Nudeln" stays "Nudeln".
    private static let aliases: [(sources: [String], mentions: [String])] = [
        (ricePaperNames,
         ["Reispapier", "Reispapierblatt", "Reispapierblätter", "Reispapier Blätter",
          "Reis Papier", "Reis Papierblatt", "Reis Papierblätter", "Reispapier Blatt",
          "Reis Papier Blatt", "Reis Papier Blätter"]),
        (["Reisnudeln", "Reisbandnudeln", "Reisvermicelli", "rice noodles", "rice vermicelli"],
         ["Reisnudeln", "Reisbandnudeln", "Reis Nudeln", "Reis Bandnudeln", "Reis Band Nudeln"]),
        (["Nudeln", "Bandnudeln", "Reisnudeln", "Reisbandnudeln", "Reisvermicelli", "Glasnudeln",
          "Spaghetti", "Penne", "Farfalle", "Tagliatelle", "Maccheroni", "Fusilli", "Pasta", "Orzo"],
         ["Nudeln", "Pasta"]),
        (["Salat", "Eisbergsalat", "Butterlatich", "Kopfsalat", "Römersalat", "Romana", "Cos Salat",
          "Feldsalat", "Blattsalat", "Lollo Rosso", "Lollo Bionda"], ["Salat"]),
        (["Reis", "Basmatireis", "Jasminreis", "Langkornreis", "Rundkornreis", "Vollkornreis", "Sushireis"],
         ["Reis"]),
        (["Hähnchen", "Hähnchenbrust", "Hähnchenbrustfilet", "Hähnchenfilet", "Hähnchenschenkel",
          "Hähnchenflügel", "Hähnchenober und unterschenkel", "Poulet", "Huhn"], ["Hähnchen", "Huhn"]),
        (["Garnelen", "Shrimps", "Crevetten", "Scampi"], ["Garnelen", "Shrimps", "Crevetten"]),
        (["Ei", "Eier", "Eiern", "Eies"], ["Ei", "Eier", "Eiern", "Eies"]),
        (["Karotten", "Möhren", "Rüebli"], ["Karotten", "Möhren", "Rüebli"]),
        (["Kartoffeln", "Erdäpfel"], ["Kartoffeln", "Erdäpfel"]),
        (["Tomaten", "Kirschtomaten", "Cocktailtomaten", "Eiertomaten", "Cherrytomaten"], ["Tomaten"]),
        (["Frühlingszwiebeln", "Lauchzwiebeln", "Schlotten"], ["Frühlingszwiebeln", "Lauchzwiebeln", "Schlotten", "Frühlingszwiebelringe", "Lauchzwiebelringe"]),
        (["Zwiebeln", "Schalotten"], ["Zwiebeln"]),
        (["Olivenöl", "Rapsöl", "Sonnenblumenöl", "Sesamöl", "Kokosöl", "Kokosnussöl", "Pflanzenöl", "Öl"], ["Öl"]),
        (["Weizenmehl", "Dinkelmehl", "Roggenmehl", "Mehl"], ["Mehl"]),
        (["Fisch", "Kabeljau", "Seelachs", "Lachs", "Fischfilet", "Forelle", "Dorade"], ["Fisch"]),
        (["Joghurt", "Naturjoghurt", "griechischer Joghurt", "Jogurt"], ["Joghurt", "Jogurt"]),
        (["Paprikapulver", "Räucherpaprika"], ["Paprikapulver"]),
        (["Sojasauce", "Sojasoße"], ["Sojasauce", "Sojasoße", "Soja Sauce", "Soja Soße"]),
        (["Sahne", "Schlagsahne", "Rahm", "Schlagrahm"], ["Sahne", "Rahm"]),
        (["Sprossen", "Sojasprossen", "Mungobohnensprossen", "Keimlinge"], ["Sprossen", "Keimlinge"]),
        (["Minze", "Minzblätter", "Minzblatt"], ["Minze", "Minzblätter", "Minzblatt"]),
        (["Koriander", "Korianderblätter", "Korianderblatt"], ["Koriander", "Korianderblätter", "Korianderblatt"]),
        (["Basilikum", "Basilikumblätter", "Basilikumblatt"], ["Basilikum", "Basilikumblätter", "Basilikumblatt"]),
        (["Schnittlauch", "Schnittlauchröllchen"], ["Schnittlauch"]),
        (["Zitrone", "Zitronensaft", "Zitronenabrieb"], ["Zitrone"]),
        (["Limette", "Limettensaft", "Limettenabrieb"], ["Limette"]),
        (["Passata", "passierte Tomaten"], ["Passata", "passierte Tomaten"]),
        (["Meersalz", "Speisesalz", "Salz"], ["Salz"]),
        (["Pfeffer", "schwarzer Pfeffer", "weißer Pfeffer"], ["Pfeffer"])
    ]

    private static let aliasKeys = aliases.map { rule in
        (sources: Set(rule.sources.flatMap { inflections($0.lowercased()) }.map(compact)), mentions: rule.mentions)
    }

    private static let separator = #"[\s\p{Pd}\u00AD]+"#
    private static let leftBoundary = #"(?<![\p{L}\p{M}])"#
    private static let rightBoundary = #"(?![\p{L}\p{M}])"#
    private static let paperShortContext = #"(?=\s+(?:kurz\s+)?(?:einweich|anfeucht|in\s+(?:\p{L}+\s+){0,2}wasser\b|auf\s+(?:\p{L}+\s+){0,3}feucht\p{L}*\s))"#

    init(ingredients: [Recipe.Ingredient], reviewedAliases: [String: [String]] = [:]) {
        var explicit: [Name] = []
        var canonical: [Name] = []
        for ingredient in ingredients {
            for component in Self.components(of: ingredient.name) {
                let name = Name(text: component, iconName: component, ingredient: ingredient)
                explicit.append(name)

                let plain = Self.withoutModifiers(component)
                let base = Name(text: plain, iconName: plain, ingredient: ingredient)
                canonical.append(base)
                if plain != component { explicit.append(base) }
            }
        }

        let candidates = canonical.map { (key: Self.compact($0.text), name: $0) }
        var names = explicit
        for (sources, mentions) in Self.aliasKeys {
            let hits = candidates.filter { sources.contains($0.key) }.map(\.name)
            guard let source = Self.unambiguous(hits) else { continue }
            for mention in mentions {
                let text = mention.lowercased()
                names.append(Name(text: text, iconName: source.iconName, ingredient: source.ingredient))
            }
        }

        for ingredient in ingredients {
            let key = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let known = canonical.filter { $0.ingredient.id == ingredient.id }
            for alias in (reviewedAliases[key] ?? []).prefix(12) where (1...90).contains(alias.count) {
                let normalized = alias.lowercased()
                let source = known.first { $0.text.contains(normalized) } ?? known.first
                names.append(Name(text: normalized, iconName: source?.iconName ?? ingredient.name, ingredient: ingredient))
            }
        }

        // "Papier" and "Blatt" also occur as equipment or a unit for salad. Treat them
        // as rice paper only when the step describes soaking or laying it on a wet surface.
        let paperKeys = Set(Self.ricePaperNames.map { Self.compact($0.lowercased()) })
        let paper = Self.unambiguous(candidates.filter { paperKeys.contains($0.key) }.map(\.name))
        var uniquePatterns = Set<String>()
        var terms: [Term] = []
        for name in names {
            let pattern = Self.pattern(for: name.text)
            guard !pattern.isEmpty, uniquePatterns.insert(pattern).inserted,
                  let regex = Self.regex(pattern) else { continue }
            terms.append(Term(regex: regex, name: name))
        }
        if let paper, let regex = Self.regex("(?:papier(?:s)?|blatt(?:es|s)?|blätter(?:n)?)",
                                              suffix: Self.paperShortContext) {
            terms.append(Term(regex: regex, name: paper))
        }
        self.terms = terms
    }

    func matches(in step: String) -> [Match] {
        let bounds = NSRange(step.startIndex..., in: step)
        let hits = terms.enumerated().flatMap { index, term in
            term.regex.matches(in: step, range: bounds).map { (order: index, range: $0.range, name: term.name) }
        }.sorted { lhs, rhs in
            if lhs.range.length != rhs.range.length { return lhs.range.length > rhs.range.length }
            return lhs.order < rhs.order
        }

        var matches: [Match] = []
        for hit in hits {
            guard let range = Range(hit.range, in: step),
                  !matches.contains(where: { $0.range.overlaps(range) }) else { continue }
            matches.append(Match(range: range, ingredient: hit.name.ingredient, iconName: hit.name.iconName))
        }
        return matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func regex(_ pattern: String, suffix: String = "") -> NSRegularExpression? {
        try? NSRegularExpression(pattern: leftBoundary + pattern + rightBoundary + suffix, options: .caseInsensitive)
    }

    private static func components(of ingredient: String) -> [String] {
        let list = ingredient.lowercased()
            .replacingOccurrences(of: #"\([^()]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+(?:zum|zur|nach belieben|nach geschmack)\b[^,;/]*"#,
                                  with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+(?:oder|bzw\.?)\s+|[,;/]"#, with: "|", options: .regularExpression)
        return list.split(separator: "|").compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.first?.isLetter == true else { return nil }
            return Self.words(clean).joined(separator: " ")
        }
    }

    private static func withoutModifiers(_ name: String) -> String {
        name.replacingOccurrences(
            of: #"^(?:(?:sehr|frisch|getrocknet|tiefgekühlt|tk|bio|fein|grob|gehackt|geschält|gerieben|gewürfelt|geschnitten|gekocht|lauwarm|neutral|trocken|reif|groß|klein|ungesalzen|gesalzen|flüssig|blanchiert|salzreduziert)(?:e[nmrs]?)?\s+)+"#,
            with: "", options: .regularExpression
        )
    }

    private static func words(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-‐‑‒–—\u{00AD}")))
            .filter { !$0.isEmpty }
    }

    private static func compact(_ text: String) -> String { words(text).joined() }

    private static func unambiguous(_ names: [Name]) -> Name? {
        guard let first = names.first else { return nil }
        return names.allSatisfy {
            $0.ingredient.id == first.ingredient.id || compact($0.iconName) == compact(first.iconName)
        } ? first : nil
    }

    private static func pattern(for name: String) -> String {
        var words = words(name).map(NSRegularExpression.escapedPattern(for:))
        guard let last = words.popLast() else { return "" }
        let roots = roots(for: last)
        if last.count >= 4, last.allSatisfy(\.isLetter) {
            let anyRoot = "(?:" + roots.joined(separator: "|") + ")"
            let anyEnding = "(?:" + endings.joined(separator: "|") + ")?"
            words.append(anyRoot + anyEnding)
        } else {
            words.append(last)
        }
        return words.joined(separator: separator)
    }

    private static func inflections(_ text: String) -> [String] {
        var words = words(text)
        guard let last = words.popLast(), last.count >= 4, last.allSatisfy(\.isLetter) else { return [text] }
        return roots(for: last).flatMap { root in
            ([root] + endings.map { root + $0 }).map { (words + [$0]).joined(separator: " ") }
        }
    }

    private static func roots(for word: String) -> [String] {
        if word.count > 4, word.hasSuffix("n") || word.hasSuffix("e") {
            return [word, String(word.dropLast())]
        }
        return [word]
    }
}

struct PreparationStep: View {
    let step: String
    let mentions: IngredientMentions
    @ScaledMetric(relativeTo: .body) private var iconSize = 16.0

    var body: some View {
        var text = Text(verbatim: "")
        var cursor = step.startIndex
        for match in mentions.matches(in: step) {
            let icon = IngredientIcon(name: match.iconName, aisle: match.ingredient.aisle)
                .inlineText(size: iconSize)
            let prefix = Text(verbatim: String(step[cursor..<match.range.lowerBound]))
            let word = Text(verbatim: String(step[match.range])).bold()
            let space = Text(verbatim: "\u{00A0}")
            text = Text("\(text)\(prefix)\(icon)\(space)\(word)")
            cursor = match.range.upperBound
        }
        let suffix = Text(verbatim: String(step[cursor...]))
        return Text("\(text)\(suffix)").accessibilityLabel(step)
    }
}
