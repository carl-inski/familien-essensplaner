import Foundation

public enum PlanChange: Hashable, Sendable {
    case out(MealSlot)
    case move(MealSlot, MealSlot)

    public var source: MealSlot {
        switch self { case let .out(slot), let .move(slot, _): slot }
    }

    // Corresponds to applyChange in lib/plan-change.ts.
    public func applying(to plan: [MealPlanEntry], purchases: [Purchase], today: String)
        -> (plan: [MealPlanEntry], purchases: [Purchase])? {
        guard source.date >= today, let from = plan.first(where: { $0.slot == source }),
              from.recipeID != nil || from.leftoverOf != nil else { return nil }
        switch self {
        case .out:
            guard from.status != .cancelled else { return nil }
            return (plan.map { $0.id == from.id ? replacing($0, with: $0, cancelled: true) : $0 }, purchases)
        case let .move(_, target):
            guard target != source, target.date >= today, from.status != .cancelled else { return nil }
            let to = plan.first { $0.slot == target } ?? MealPlanEntry(
                id: "neu-\(target.date)-\(target.meal.rawValue)", date: target.date, meal: target.meal
            )
            guard from.leftoverOf != to.id, to.leftoverOf != from.id else { return nil }
            func swap(_ id: String?) -> String? {
                if id == from.id { return to.id }
                if id == to.id { return from.id }
                return id
            }
            let rest = plan.filter { $0.id != from.id && $0.id != to.id }.map {
                MealPlanEntry(id: $0.id, date: $0.date, meal: $0.meal, recipeID: $0.recipeID,
                              leftoverOf: swap($0.leftoverOf), cookID: $0.cookID, secondCookID: $0.secondCookID,
                              servingsOverride: $0.servingsOverride, status: $0.status, note: $0.note, shoppedAt: $0.shoppedAt,
                              familyGuests: $0.familyGuests)
            }
            let moved = purchases.map {
                Purchase(id: $0.id, dishID: swap($0.dishID), key: $0.key, name: $0.name, amount: $0.amount,
                         unit: $0.unit, boughtAt: $0.boughtAt, isStock: $0.isStock, boughtBy: $0.boughtBy)
            }
            let adjusted = rest + [replacing(from, with: to), replacing(to, with: from)]
            let changedIDs: Set<String> = [from.id, to.id]
            for entry in adjusted where entry.status != .cancelled {
                guard let originID = entry.leftoverOf,
                      changedIDs.contains(entry.id) || changedIDs.contains(originID) else { continue }
                if let origin = adjusted.first(where: { $0.id == originID }),
                   !origin.canBeLeftoverSource(for: entry.slot) { return nil }
            }
            return (adjusted, moved)
        }
    }

    private func replacing(_ slot: MealPlanEntry, with dish: MealPlanEntry, cancelled: Bool = false) -> MealPlanEntry {
        MealPlanEntry(id: slot.id, date: slot.date, meal: slot.meal, recipeID: dish.recipeID,
                      leftoverOf: dish.leftoverOf, cookID: slot.cookID, secondCookID: slot.secondCookID,
                      servingsOverride: cancelled ? slot.servingsOverride : nil, status: cancelled ? .cancelled : .planned,
                      note: slot.note, shoppedAt: cancelled ? slot.shoppedAt : nil, familyGuests: slot.familyGuests)
    }

    public static func shoppingImpact(before: ShoppingResult, after: ShoppingResult) -> [String] {
        struct Row {
            var amount: Double?
            let name: String
            let unit: String?
            var line: String {
                amount.map { Quantity(amount: $0, unit: unit).formatted + " " + name } ?? name
            }
        }
        func rows(_ result: ShoppingResult) -> [String: Row] {
            var output: [String: Row] = [:]
            for part in result.open.flatMap(\.parts) {
                if let prior = output[part.key], let left = prior.amount, let right = part.amount {
                    output[part.key]?.amount = left + right
                } else {
                    output[part.key] = Row(amount: part.amount, name: part.name, unit: part.unit)
                }
            }
            return output
        }
        let old = rows(before)
        let new = rows(after)
        var more: [String] = []
        var less: [String] = []
        for key in Set(old.keys).union(new.keys).sorted() {
            switch (old[key], new[key]) {
            case let (nil, row?): more.append(row.line)
            case let (row?, nil): less.append(row.line)
            case let (old?, new?):
                guard let a = old.amount, let b = new.amount, abs(a - b) > 0.0005 else { continue }
                var delta = new
                delta.amount = (abs(a - b) * 1000).rounded() / 1000
                if b > a { more.append(delta.line) } else { less.append(delta.line) }
            default: break
            }
        }
        let existingStock = Set(before.stock.map(\.id))
        let saved = after.stock.filter { !existingStock.contains($0.id) }.map(\.text)
        var output: [String] = []
        if !more.isEmpty { output.append("Zusätzlich auf der Liste: " + more.joined(separator: ", ") + ".") }
        if !less.isEmpty { output.append("Nicht mehr nötig: " + less.joined(separator: ", ") + ".") }
        if !saved.isEmpty { output.append("Schon gekauft und bleibt da: " + saved.joined(separator: ", ") + ".") }
        return output.isEmpty ? ["Die Einkaufsliste bleibt, wie sie ist."] : output
    }
}
