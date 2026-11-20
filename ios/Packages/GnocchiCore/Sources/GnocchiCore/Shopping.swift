import Foundation

public struct ShoppingIngredient: Sendable {
    public let name: String
    public let quantity: Quantity?
    public let aisle: String?

    public init(name: String, quantity: Quantity?, aisle: String? = nil) {
        self.name = name
        self.quantity = quantity
        self.aisle = aisle
    }
}

public struct ShoppingRecipe: Sendable {
    public let title: String
    public let servings: Int?
    public let ingredients: [ShoppingIngredient]

    public init(title: String, servings: Int?, ingredients: [ShoppingIngredient]) {
        self.title = title
        self.servings = servings
        self.ingredients = ingredients
    }
}

public struct Purchase: Identifiable, Sendable {
    public let id: String
    public let dishID: String?
    public let key: String
    public let name: String
    public let amount: Double?
    public let unit: String?
    public let boughtAt: Date
    public let isStock: Bool
    public let boughtBy: String?

    public init(id: String, dishID: String?, key: String, name: String, amount: Double?, unit: String?,
                boughtAt: Date, isStock: Bool = false, boughtBy: String? = nil) {
        self.id = id
        self.dishID = dishID
        self.key = key
        self.name = name
        self.amount = amount
        self.unit = unit
        self.boughtAt = boughtAt
        self.isStock = isStock
        self.boughtBy = boughtBy
    }
}

public struct ShoppingPart: Sendable {
    public let dishID: String
    public let key: String
    public let name: String
    public let amount: Double?
    public let unit: String?
}

public struct ShoppingLine: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let text: String
    public let aisle: String
    public var recipeTitles: [String] = []
    public var parts: [ShoppingPart] = []
    public var purchaseIDs: [String] = []
    public var usesStock = false
    public var fromStock = false
    public var boughtBy: String? = nil
}

public struct ShoppingResult: Sendable {
    public let open: [ShoppingLine]
    public let stock: [ShoppingLine]
    public let bought: [ShoppingLine]
    public let covered: Set<String>
}

public enum Shopping {
    public static let stockDays = 21
    public static let horizonDays = 42

    // Matches the Bring! cache version in the web shopping list.
    public static func exportVersion(_ lines: [String]) -> String {
        let hash = lines.joined(separator: "\n").unicodeScalars.reduce(UInt32(5381)) { hash, scalar in
            let code = scalar.value
            let firstUTF16 = code <= 0xFFFF ? code : 0xD800 + ((code - 0x10000) >> 10)
            return (hash &* 33) ^ firstUTF16
        }
        return String(hash, radix: 36)
    }

    public static func stockEntry(_ text: String) -> (name: String, quantity: Quantity?, key: String)? {
        let line = Quantity.splitIngredientLine(text)
        let name = IngredientName.display(line.name).trimmed
        guard !name.isEmpty else { return nil }
        let quantity = line.amount.flatMap(Quantity.parseAmount).flatMap { original -> Quantity? in
            guard original.amount > 0 else { return nil }
            switch original.unit {
            case "kg": return Quantity(amount: round(original.amount * 1_000), unit: "g")
            case "l": return Quantity(amount: round(original.amount * 1_000), unit: "ml")
            default: return original
            }
        }
        return (name, quantity, IngredientName.shoppingKey(name) + "|" + (quantity?.unit ?? ""))
    }

    public static func isShoppable(_ entry: MealPlanEntry, today: String) -> Bool {
        entry.recipeID != nil && entry.leftoverOf == nil && entry.status == .planned && entry.date >= today
    }

    public static func calculate(
        plan: [MealPlanEntry], recipes: [String: ShoppingRecipe], members: [Member], attendance: [Attendance],
        pantry: Set<String>, purchases: [Purchase], today: String, now: Date, including: Set<String>? = nil
    ) -> ShoppingResult {
        let relevant = purchases.filter { !$0.key.hasPrefix("x:") }
        let byDish = Dictionary(grouping: relevant.compactMap { purchase in
            purchase.dishID.map { ($0, purchase) }
        }, by: { $0.0 }).mapValues { $0.map(\.1) }
        let dishes = plan.filter { isShoppable($0, today: today) && recipes[$0.recipeID ?? ""] != nil }
        let dishIDs = Set(dishes.map(\.id))
        let planByID = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0) })
        let freshSince = now.addingTimeInterval(Double(-stockDays) * 86_400)
        var stock = OrderedItems<Stock>()
        var open = OrderedItems<Open>()
        var covered: Set<String> = []
        var missing: [String: Set<String>] = [:]

        for dish in dishes {
            guard let recipeID = dish.recipeID, let recipe = recipes[recipeID] else { continue }
            let mine = byDish[dish.id] ?? []
            if dish.shoppedAt != nil && mine.isEmpty {
                covered.insert(dish.id)
                continue
            }
            let servings = Planning.servings(for: dish, in: plan, members: members, attendance: attendance)
            let needs = ingredients(recipe: recipe, servings: servings, pantry: pantry)
            let keys = Set(needs.map(\.key))
            let boughtByKey = Dictionary(grouping: mine, by: \.key)
            var hasDeficit = false
            for ingredient in needs {
                let purchased = boughtByKey[ingredient.key] ?? []
                let bought = purchased.reduce(0) { $0 + ($1.amount ?? 0) }
                let deficit: Double?
                if let needed = ingredient.amount {
                    deficit = round(max(0, needed - bought))
                    if bought > needed + 0.0005 {
                        addStock(key: ingredient.key, name: ingredient.name, amount: round(bought - needed),
                                 unit: ingredient.unit, ids: purchased.map(\.id), to: &stock)
                    }
                } else {
                    deficit = purchased.isEmpty ? nil : 0
                }
                guard deficit != 0 else { continue }
                hasDeficit = true
                guard including?.contains(dish.id) ?? true else { continue }
                let part = ShoppingPart(dishID: dish.id, key: ingredient.key, name: ingredient.name,
                                        amount: deficit, unit: ingredient.unit)
                if var current = open[ingredient.key] {
                    if let amount = current.amount, let deficit { current.amount = round(amount + deficit) }
                    current.parts.append(part)
                    if !current.recipes.contains(recipe.title) { current.recipes.append(recipe.title) }
                    current.originalText = nil
                    open[ingredient.key] = current
                } else {
                    open[ingredient.key] = Open(name: ingredient.name, aisle: ingredient.aisle, amount: deficit,
                                                unit: ingredient.unit, parts: [part], recipes: [recipe.title],
                                                originalText: purchased.isEmpty ? ingredient.composite : nil)
                }
            }
            if hasDeficit { missing[dish.id] = keys }
            else if !mine.isEmpty { covered.insert(dish.id) }
            for purchase in mine where !keys.contains(purchase.key) && purchase.boughtAt >= freshSince {
                addStock(purchase, to: &stock)
            }
        }

        for purchase in relevant where purchase.boughtAt >= freshSince {
            if let dishID = purchase.dishID {
                guard !dishIDs.contains(dishID), let entry = planByID[dishID], entry.status != .cooked else { continue }
            }
            addStock(purchase, to: &stock)
        }

        let unknownStock = Set(stock.values.filter { $0.amount == nil }.map { IngredientName.shoppingKey($0.name) })
        for key in open.keys {
            guard var row = open[key] else { continue }
            guard let existing = stock[key] else {
                if unknownStock.contains(IngredientName.shoppingKey(row.name)) { open[key] = nil }
                continue
            }
            if let amount = row.amount, let stockAmount = existing.amount, amount > stockAmount {
                row.amount = round(amount - stockAmount)
                row.originalText = nil
                row.usesStock = true
                open[key] = row
            } else {
                open[key] = nil
            }
        }
        for (dishID, keys) in missing where keys.allSatisfy({ open[$0] == nil }) {
            covered.insert(dishID)
        }

        let groups = Dictionary(grouping: open.values, by: { IngredientName.shoppingKey($0.name) })
        let openLines = groups.compactMap { key, rows -> ShoppingLine? in
            guard let first = rows.first else { return nil }
            let amounts = rows.compactMap { row in row.amount.map { Quantity(amount: $0, unit: row.unit) } }
            let name = shortest(rows.map(\.name))
            let text = rows.count == 1 ? first.originalText : nil
            return ShoppingLine(id: key, name: name, text: text ?? line(name, quantities: merged(amounts)), aisle: first.aisle,
                                recipeTitles: unique(rows.flatMap(\.recipes)), parts: rows.flatMap(allocated),
                                usesStock: rows.contains(where: \.usesStock))
        }

        let cutoff = now.addingTimeInterval(-12 * 3_600)
        let recent = relevant.filter { $0.boughtAt >= cutoff && !($0.isStock && $0.dishID == nil) }
        let recentlyBought = Dictionary(grouping: recent, by: { IngredientName.shoppingKey($0.name) })
            .compactMap { key, purchases -> ShoppingLine? in
                guard groups[key] == nil, let first = purchases.first else { return nil }
                var amounts = OrderedItems<Stock>()
                for purchase in purchases {
                    addStock(key: purchase.unit ?? "", name: purchase.name, amount: purchase.amount, unit: purchase.unit,
                             ids: [purchase.id], to: &amounts)
                }
                return ShoppingLine(id: key, name: first.name, text: line(first.name, quantities: amounts.values.compactMap(\.quantity)),
                                    aisle: Aisles.forIngredient(first.name), purchaseIDs: purchases.map(\.id),
                                    fromStock: purchases.allSatisfy(\.isStock), boughtBy: first.boughtBy)
            }

        let stockLines = stock.keys.compactMap { key in
            stock[key].map { item in
                ShoppingLine(id: key, name: item.name, text: line(item.name, quantities: [item.quantity].compactMap { $0 }),
                             aisle: Aisles.forIngredient(item.name), purchaseIDs: unique(item.ids))
            }
        }
        return ShoppingResult(open: openLines.sorted(by: byAisle), stock: stockLines.sorted(by: byName),
                              bought: recentlyBought.sorted(by: byAisle), covered: covered)
    }

    private struct Need {
        let name: String
        let aisle: String
        let amount: Double?
        let unit: String?
        let composite: String?
        var key: String { IngredientName.shoppingKey(name) + "|" + (unit ?? "") }
    }

    private struct Stock {
        let name: String
        var amount: Double?
        let unit: String?
        var ids: [String]
        var quantity: Quantity? { amount.map { Quantity(amount: $0, unit: unit) } }
    }

    private struct Open {
        let name: String
        let aisle: String
        var amount: Double?
        let unit: String?
        var parts: [ShoppingPart]
        var recipes: [String]
        var originalText: String?
        var usesStock = false
    }

    private static func ingredients(recipe: ShoppingRecipe, servings: Int, pantry: Set<String>) -> [Need] {
        guard servings != 0 else { return [] }
        let base = recipe.servings.flatMap { $0 == 0 ? nil : $0 }
        let quantities = recipe.ingredients.compactMap { ingredient -> (String, String, Quantity?)? in
            guard !ingredient.name.trimmed.lowercased().matches(pattern: #"^wasser\b"#),
                  let remainder = Pantry.remaining(ingredient.name, in: pantry) else { return nil }
            var name = IngredientName.display(remainder)
            let quantity = ingredient.quantity.map { quantity in
                base.map { quantity.scaled(by: Double(servings) / Double($0)) } ?? quantity
            }
            var adjusted = quantity
            if let quantity, quantity.unit == nil, name.lowercased().matches(pattern: #"^.+?zehen?$"#) {
                name = name.replacing(pattern: #"zehen?$"#, with: "", ignoreCase: true)
                adjusted = Quantity(amount: quantity.amount, unit: "Zehen")
            }
            return (name, ingredient.aisle ?? Aisles.forIngredient(name), adjusted)
        }
        let grouped = Dictionary(grouping: quantities, by: { IngredientName.shoppingKey($0.0) })
        return unique(quantities.map { IngredientName.shoppingKey($0.0) }).compactMap { key in
            guard let rows = grouped[key], let first = rows.first else { return nil }
            let amounts = merged(rows.compactMap(\.2))
            let name = shortest(rows.map(\.0))
            return Need(name: name, aisle: first.1, amount: amounts.first?.amount, unit: amounts.first?.unit,
                        composite: amounts.count > 1 ? line(name, quantities: amounts) : nil)
        }
    }

    private static func merged(_ quantities: [Quantity]) -> [Quantity] {
        struct UnitTotal {
            var amount: Double = 0
            var rounding: Double?
        }
        let volume = quantities.contains { $0.unit == "ml" || $0.unit == "l" }
        let tablespoons = quantities.contains { $0.unit == "EL" }
        var totals = OrderedItems<UnitTotal>()
        for quantity in quantities {
            let (unit, scale, rounding): (String?, Double, Double?) = switch quantity.unit {
            case "kg": ("g", 1_000, nil)
            case "l": ("ml", 1_000, nil)
            case "EL" where volume: ("ml", 15, 5)
            case "TL" where volume: ("ml", 5, 5)
            case "TL" where tablespoons: ("EL", 1.0 / 3, 0.5)
            default: (quantity.unit, 1, nil)
            }
            let key = unit ?? ""
            var entry = totals[key] ?? UnitTotal()
            entry.amount += quantity.amount * scale
            entry.rounding = entry.rounding ?? rounding
            totals[key] = entry
        }
        return totals.keys.compactMap { key in
            totals[key].map { total in
                let amount = total.rounding.map { ceil(total.amount / $0) * $0 } ?? round(total.amount)
                return Quantity(amount: amount, unit: key.isEmpty ? nil : key)
            }
        }.enumerated()
            .sorted { (unitRank($0.element.unit), $0.offset) < (unitRank($1.element.unit), $1.offset) }
            .map(\.element)
    }

    private static func unitRank(_ unit: String?) -> Int {
        switch unit {
        case "g", "ml": 0
        case "EL", "TL": 1
        case nil: 2
        default: 3
        }
    }

    private static func allocated(_ row: Open) -> [ShoppingPart] {
        var left = row.amount
        return row.parts.compactMap { part in
            let amount: Double?
            if let remaining = left, let needed = part.amount {
                amount = round(min(remaining, needed))
                left = round(remaining - (amount ?? 0))
            } else {
                amount = nil
            }
            guard amount == nil || (amount ?? 0) > 0 else { return nil }
            return ShoppingPart(dishID: part.dishID, key: part.key, name: row.name, amount: amount, unit: part.unit)
        }
    }

    private static func addStock(_ purchase: Purchase, to stock: inout OrderedItems<Stock>) {
        addStock(key: purchase.key, name: purchase.name, amount: purchase.amount, unit: purchase.unit,
                 ids: [purchase.id], to: &stock)
    }

    private static func addStock(key: String, name: String, amount: Double?, unit: String?, ids: [String],
                                 to stock: inout OrderedItems<Stock>) {
        if var current = stock[key] {
            current.amount = current.amount.flatMap { have in amount.map { round(have + $0) } }
            current.ids.append(contentsOf: ids)
            stock[key] = current
        } else {
            stock[key] = Stock(name: name, amount: amount, unit: unit, ids: ids)
        }
    }

    private static func line(_ name: String, quantities: [Quantity]) -> String {
        quantities.isEmpty ? name : quantities.map(\.formatted).joined(separator: " + ") + " " + name
    }

    private static func byAisle(_ lhs: ShoppingLine, _ rhs: ShoppingLine) -> Bool {
        let a = Aisles.rank(lhs.aisle)
        let b = Aisles.rank(rhs.aisle)
        return a == b ? byName(lhs, rhs) : a < b
    }

    private static func byName(_ lhs: ShoppingLine, _ rhs: ShoppingLine) -> Bool {
        lhs.name.compare(rhs.name, locale: Locale(identifier: "de_DE")) == .orderedAscending
    }

    private static func round(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }

    private static func shortest(_ names: [String]) -> String {
        names.min { $0.utf16.count < $1.utf16.count } ?? ""
    }

    private static func unique<T: Hashable>(_ input: [T]) -> [T] {
        var known: Set<T> = []
        return input.filter { known.insert($0).inserted }
    }
}

private struct OrderedItems<Value> {
    private var dictionary: [String: Value] = [:]
    private(set) var keys: [String] = []
    var values: [Value] { keys.compactMap { dictionary[$0] } }

    subscript(key: String) -> Value? {
        get { dictionary[key] }
        set {
            if dictionary[key] == nil && newValue != nil { keys.append(key) }
            if newValue == nil { keys.removeAll { $0 == key } }
            dictionary[key] = newValue
        }
    }
}
