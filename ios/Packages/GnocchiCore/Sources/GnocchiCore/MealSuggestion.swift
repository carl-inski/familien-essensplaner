public enum MealSuggestion {
    public struct Candidate: Sendable {
        public let id: String
        public let cookbookID: String?
        public let tags: [String]
        public let categories: [String]

        public init(id: String, cookbookID: String?, tags: [String], categories: [String]) {
            self.id = id
            self.cookbookID = cookbookID
            self.tags = tags
            self.categories = categories
        }
    }

    public struct Planned: Sendable {
        public let slot: MealSlot
        public let recipeID: String

        public init(slot: MealSlot, recipeID: String) {
            self.slot = slot
            self.recipeID = recipeID
        }
    }

    private static let snackTags: Set<String> = ["snack", "süß", "dessert", "backen", "kuchen"]
    private static let excludedTags = snackTags.union(["frühstück", "getränk"])

    private static func isCandidate(_ recipe: Candidate, for meal: Meal) -> Bool {
        let tags = (recipe.tags + recipe.categories).map { $0.lowercased() }
        switch meal {
        case .breakfast: return tags.contains("frühstück")
        case .snack: return tags.contains(where: snackTags.contains)
        case .lunch, .dinner: return !tags.contains(where: excludedTags.contains)
        }
    }

    public static func daysSince(_ lastCooked: String, today: String) -> Int? {
        guard let first = BerlinDay.date(for: lastCooked), let last = BerlinDay.date(for: today) else { return nil }
        return BerlinDay.calendar.dateComponents([.day], from: first, to: last).day
    }

    public static func pick(from recipes: [Candidate], lastCooked: [String: String], plan: [Planned],
                            slot: MealSlot, today: String, avoiding: Set<String>, random: Double) -> Candidate? {
        let planned = Set(plan.filter { $0.slot != slot }.map(\.recipeID))
        let weighted = recipes.compactMap { recipe -> (Candidate, Double)? in
            guard !avoiding.contains(recipe.id), !planned.contains(recipe.id),
                  isCandidate(recipe, for: slot.meal) else { return nil }
            let age = lastCooked[recipe.id].flatMap { daysSince($0, today: today) }
            if let age, age < 14 { return nil }
            let weight = Double(age.map { min($0, 120) } ?? 140) * (recipe.cookbookID == nil ? 1 : 1.3)
            return (recipe, max(weight, 1))
        }
        var threshold = random * weighted.reduce(0) { $0 + $1.1 }
        for (candidate, weight) in weighted {
            threshold -= weight
            if threshold <= 0 { return candidate }
        }
        return weighted.last?.0
    }
}
