import Foundation

public struct DecideCandidate: Sendable {
    public let id: String
    public let cookbookID: String?
    public let tags: [String]
    public let categories: [String]
    public let folderID: String?

    public init(id: String, cookbookID: String?, tags: [String], categories: [String], folderID: String?) {
        self.id = id
        self.cookbookID = cookbookID
        self.tags = tags
        self.categories = categories
        self.folderID = folderID
    }
}

public enum DecideCandidates {
    // lib/decide.ts pickCandidates and the rules in lib/suggest.ts.
    private static let notDinner: Set<String> = ["snack", "süß", "dessert", "backen", "kuchen", "frühstück", "getränk"]

    public static func pick(_ recipes: [DecideCandidate], latest: [String: String], plan: [MealPlanEntry],
                            today: String, seed: Int, count: Int, folderID: String?) -> [String] {
        guard count > 0 else { return [] }
        var random = SeededRandom(seed: seed)
        let eligible = recipes.filter { recipe in
            if let folderID { return recipe.folderID == folderID }
            return !(recipe.tags + recipe.categories).contains { notDinner.contains($0.lowercased()) }
        }
        let scheduledIDs = Set(plan.filter { $0.status != .cancelled }.compactMap(\.recipeID))
        var bag = eligible.compactMap { recipe -> (id: String, weight: Double)? in
            let days = latest[recipe.id].flatMap { daysBetween($0, today) }
            guard !scheduledIDs.contains(recipe.id), (days ?? 140) >= 14 else { return nil }
            let weight = days.map { Double(min($0, 120)) } ?? 140
            return (recipe.id, max(1, weight * (recipe.cookbookID == nil ? 1 : 1.3)))
        }
        var choices: [String] = []
        while choices.count < count && !bag.isEmpty {
            var draw = random.next() * bag.reduce(0) { $0 + $1.weight }
            let index = bag.indices.dropLast().first {
                draw -= bag[$0].weight
                return draw <= 0
            } ?? bag.count - 1
            choices.append(bag.remove(at: index).id)
        }
        if choices.count < count {
            let rest = shuffled(eligible.map(\.id).filter { !choices.contains($0) }, &random)
            choices.append(contentsOf: rest.prefix(count - choices.count))
        }
        return choices
    }

    private static func daysBetween(_ from: String, _ to: String) -> Int? {
        guard let start = BerlinDay.date(for: from), let end = BerlinDay.date(for: to) else { return nil }
        return BerlinDay.calendar.dateComponents([.day], from: start, to: end).day
    }
}
