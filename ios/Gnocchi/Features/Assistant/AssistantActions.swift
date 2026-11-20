import Foundation
import GnocchiCore
import Supabase

struct AssistantPreview {
    struct Assignment {
        let recipeID: String
        let entry: MealPlanEntry?
    }

    let lines: [String]
    var householdID: String?
    var assignments: [MealSlot: Assignment] = [:]
    var planChange: PlanChangePreview?
}

struct PlanChangePreview {
    let change: PlanChange
    let householdID: String
    let source: MealPlanEntry
    let destination: MealPlanEntry?
    let lines: [String]

    func matches(_ other: PlanChangePreview) -> Bool {
        change == other.change && householdID == other.householdID && lines == other.lines &&
            source.planningSnapshot == other.source.planningSnapshot &&
            destination?.planningSnapshot == other.destination?.planningSnapshot
    }
}

enum AssistantActions {
    private struct PlanItem: Sendable {
        let slot: MealSlot
        let recipeID: String
        let reason: String?
    }

    @MainActor
    static func preview(_ tool: AssistantTool, input: JSONObject, household: HouseholdStore) async throws -> AssistantPreview {
        switch tool {
        case .plan, .batch:
            let items = try planItems(tool, input)
            guard let family = household.household else { throw invalid }
            let current = try await entries(items.map(\.slot), household: household, includingEmpty: true)
            guard household.household?.id == family.id else { throw invalid }
            let entriesBySlot = Dictionary(uniqueKeysWithValues: current.map { ($0.slot, $0) })
            let lines = try items.map { item in
                let recipe = try findRecipe(item.recipeID, household: household)
                let replacement = entriesBySlot[item.slot].flatMap { old -> String? in
                    guard !old.allowsSuggestion, !old.alreadyPlansRecipe(item.recipeID) else { return nil }
                    return old.status == .cancelled ? "Ausgefallener Termin" : entryTitle(old, household: household)
                }
                return [slotLabel(item.slot) + " · " + recipe.title, replacement.map { "Ersetzt „\($0)“." }, item.reason]
                    .compactMap { $0 }.joined(separator: "\n")
            }
            let assignments = Dictionary(uniqueKeysWithValues: items.map { item in
                (item.slot, AssistantPreview.Assignment(recipeID: item.recipeID, entry: entriesBySlot[item.slot]))
            })
            return AssistantPreview(lines: lines, householdID: family.id, assignments: assignments)
        case .attendance:
            let (slot, member, status) = try attendance(input, household: household)
            return AssistantPreview(lines: [slotLabel(slot), "\(member.name) \(status == .present ? "isst mit." : "isst nicht mit.")"])
        case .note:
            let recipe = try findRecipe(try required("rezept_id", in: input), household: household)
            return AssistantPreview(lines: [recipe.title, try required("text", in: input)])
        case .recipe:
            let draft = try recipeDraft(input)
            return AssistantPreview(lines: [draft.title, "\(draft.ingredients.count) Zutaten"])
        case .book:
            return AssistantPreview(lines: [try required("titel", in: input), input["verlag"]?.stringValue].compactMap { $0 })
        case .remove:
            let slots = try list(input).map { try slot($0) }
            let current = try await entries(slots, household: household)
            guard !current.isEmpty else { throw AssistantFailure.message("Hier ist kein Gericht eingeplant.") }
            return AssistantPreview(lines: current.map { "\(slotLabel($0.slot)) · \(entryTitle($0, household: household))" })
        case .change:
            let preview = try await previewChange(parseChange(input), household: household)
            return AssistantPreview(lines: preview.lines, planChange: preview)
        }
    }

    @MainActor
    static func apply(_ tool: AssistantTool, input: JSONObject, household: HouseholdStore,
                      confirmed: AssistantPreview? = nil) async throws -> String {
        guard let family = household.household else { throw invalid }
        let db = Backend.client
        switch tool {
        case .plan, .batch:
            let items = try planItems(tool, input)
            guard let confirmed, confirmed.householdID == family.id else { throw invalid }
            let assignments = try items.map { item in
                _ = try findRecipe(item.recipeID, household: household)
                guard let approved = confirmed.assignments[item.slot], approved.recipeID == item.recipeID else { throw invalid }
                return (item, approved.entry)
            }
            if household.isDemo || assignments.count == 1 {
                guard !household.saving else { throw invalid }
                if household.isDemo {
                    for (item, expected) in assignments {
                        let current = household.plan.first { $0.slot == item.slot }
                        guard current?.schedulingSnapshot == expected?.schedulingSnapshot else { throw planChanged }
                    }
                }
                for (item, expected) in assignments {
                    guard await household.scheduleRecipe(item.recipeID, at: item.slot, expected: expected) else {
                        if let error = household.error {
                            household.error = nil
                            throw AssistantFailure.message(error)
                        }
                        throw planChanged
                    }
                }
            } else {
                let rows: [AnyJSON] = assignments.map { item, expected in
                    .object(["date": .string(item.slot.date), "meal": .string(item.slot.meal.rawValue),
                             "recipe_id": .string(item.recipeID), "expected": expected?.schedulingSnapshot ?? .null])
                }
                let params: JSONObject = ["p_household": .string(family.id), "p_assignments": .array(rows)]
                do {
                    try await db.rpc("ep_assistant_schedule_checked", params: params).execute()
                } catch let error as PostgrestError where error.code == "PT409" {
                    throw planChanged
                }
                if let start = household.weekStart { await household.loadWeek(from: start) }
            }
            return items.count == 1 ? "Gericht eingeplant." : "\(items.count) Gerichte eingeplant."
        case .attendance:
            let (slot, member, status) = try attendance(input, household: household)
            if household.isDemo {
                await household.setAttendance(for: member, at: slot, status: status, guests: 0)
            } else {
                let payload: JSONObject = ["member_id": .string(member.id), "date": .string(slot.date),
                                           "meal": .string(slot.meal.rawValue), "status": .string(status.rawValue),
                                           "guests": .integer(0)]
                try await db.from("ep_attendance").upsert(payload, onConflict: "member_id,date,meal").execute()
                if let start = household.weekStart { await household.loadWeek(from: start) }
            }
            return "Anwesenheit geändert."
        case .note:
            let recipe = try findRecipe(try required("rezept_id", in: input), household: household)
            let note = try required("text", in: input)
            guard note.count <= 2000 else { throw invalid }
            try await household.saveRecipeNote(id: UUID().uuidString, recipeID: recipe.id, body: note)
            return "Notiz zu „\(recipe.title)“ ergänzt."
        case .book:
            let title = try required("titel", in: input)
            guard title.count <= 200, !household.cookbooks.contains(where: { $0.title.localizedStandardCompare(title) == .orderedSame }) else {
                throw AssistantFailure.message("Das Buch steht bereits im Regal oder der Titel ist zu lang.")
            }
            let authors = (input["autoren"]?.arrayValue ?? []).compactMap(\.stringValue)
            let isbn = input["isbn"]?.stringValue?.uppercased().filter { "0123456789X".contains($0) }
            let validISBN = isbn.flatMap { [10, 13].contains($0.count) ? $0 : nil }
            let year = input["jahr"]?.intValue.flatMap { (1800...2100).contains($0) ? $0 : nil }
            let book = Cookbook(id: UUID().uuidString, title: title, authors: Array(authors.prefix(6)),
                                publisher: input["verlag"]?.stringValue, year: year, isbn: validISBN,
                                coverPath: nil, notes: nil)
            try await household.saveCookbook(book, existing: false)
            return "„\(title)“ steht jetzt im Regal."
        case .remove:
            let slots = try list(input).map { try slot($0) }
            let current = try await entries(slots, household: household)
            guard !current.isEmpty else { throw invalid }
            let patch: JSONObject = ["recipe_id": .null, "leftover_of": .null, "status": .string("geplant"), "servings_override": .null]
            if household.isDemo {
                for entry in current { _ = await household.saveMeal(at: entry.slot, changes: patch) }
            } else {
                try await db.from("ep_meal_plan").update(patch).eq("household_id", value: family.id)
                    .in("id", values: current.map(\.id)).execute()
                if let start = household.weekStart { await household.loadWeek(from: start) }
            }
            return "Gerichte aus dem Wochenplan entfernt."
        case .change:
            let change = try parseChange(input)
            guard let preview = confirmed?.planChange, preview.change == change else { throw invalid }
            try await applyPlanChange(preview, household: household)
            return "Wochenplan geändert."
        case .recipe: throw invalid
        }
    }

    static func recipeDraft(_ input: JSONObject) throws -> RecipeDraft {
        guard let recipe = input["rezept"]?.objectValue else { throw invalid }
        var draft = RecipeDraft()
        func value(_ key: String) -> String { recipe[key]?.stringValue ?? "" }
        func number(_ key: String) -> String { recipe[key]?.intValue.map(String.init) ?? "" }
        draft.title = try required("title", in: recipe)
        draft.subtitle = value("subtitle")
        draft.servings = number("servings")
        draft.servingsText = value("servings_text")
        draft.timeMin = number("time_min")
        draft.timeText = value("time_text")
        draft.diet = recipe["diet"]?.stringValue
        draft.categoryText = (recipe["categories"]?.arrayValue ?? []).compactMap(\.stringValue).joined(separator: " / ")
        draft.steps = (recipe["steps"]?.arrayValue ?? []).compactMap(\.stringValue).joined(separator: "\n\n")
        draft.tip = value("tip")
        draft.nutritionText = value("nutrition_text")
        draft.ingredients = (recipe["ingredients"]?.arrayValue ?? []).compactMap { entry in
            guard let ingredient = entry.objectValue, let name = try? required("name", in: ingredient) else { return nil }
            var row = RecipeDraft.Ingredient()
            row.name = name
            row.amount = ingredient["amount"]?.stringValue ?? ""
            row.group = ingredient["group"]?.stringValue ?? ""
            return row
        }
        return draft
    }

    private static var invalid: AssistantFailure { .message("Der Vorschlag ist unvollständig oder nicht mehr verfügbar.") }
    private static var planChanged: AssistantFailure { .planChanged }

    @MainActor
    static func previewChange(_ change: PlanChange, household: HouseholdStore) async throws -> PlanChangePreview {
        guard let family = household.household else { throw invalid }
        let today = BerlinDay.today()
        let horizon = BerlinDay.adding(Shopping.horizonDays, to: today)
        let now = Date.now
        let shopping = ShoppingStore()
        if !household.isDemo {
            await shopping.load(family: family, members: household.members, today: today)
            guard shopping.loaded else { throw AssistantFailure.message("Der Einkauf konnte für die Vorschau nicht geladen werden.") }
        }
        var plan = household.isDemo ? household.plan : shopping.plan
        let target: MealSlot? = if case let .move(_, target) = change { target } else { nil }
        if !household.isDemo {
            let outsideHorizon = Set([change.source.date, target?.date].compactMap { $0 }.filter { $0 > horizon })
            for day in outsideHorizon {
                plan += try await household.plannedMeals(from: day, through: day)
            }
        }
        guard household.household?.id == family.id else { throw invalid }
        let presence = household.isDemo ? household.attendance : shopping.attendance
        let purchases = shopping.purchases
        guard let after = change.applying(to: plan, purchases: purchases, today: today),
              let source = plan.first(where: { $0.slot == change.source }) else { throw invalid }
        let destination = plan.first { $0.slot == target }
        let name = entryTitle(source, household: household)
        var lines: [String]
        switch change {
        case .out:
            guard source.status != .cooked else { throw invalid }
            lines = ["\(slotLabel(source.slot)) · \(name) fällt aus."]
        case let .move(_, target):
            lines = ["\(name): \(slotLabel(source.slot)) → \(slotLabel(target))"]
            if let other = destination, other.recipeID != nil || other.leftoverOf != nil {
                lines.append("\(entryTitle(other, household: household)) wechselt zu \(slotLabel(source.slot)).")
            }
            if source.date <= horizon, target.date <= horizon, source.recipeID != nil,
               let moved = after.plan.first(where: { $0.slot == target }) {
                let previous = Planning.servings(for: source, in: plan, members: household.members, attendance: presence)
                let next = Planning.servings(for: moved, in: after.plan, members: household.members, attendance: presence)
                if previous != next { lines.append("Portionen: \(next) statt \(previous).") }
                if next == 0 { lines.append("Dann isst niemand mit.") }
            }
        }
        let catalog = Dictionary(uniqueKeysWithValues: household.recipes.map { ($0.id, $0.shoppingRecipe) })
        let recipes = catalog.merging(shopping.recipes) { _, current in current }
        func calculate(_ plan: [MealPlanEntry], _ purchases: [Purchase]) -> ShoppingResult {
            Shopping.calculate(plan: plan.filter { $0.date <= horizon }, recipes: recipes, members: household.members, attendance: presence,
                               pantry: shopping.pantry, purchases: purchases, today: today, now: now)
        }
        lines += PlanChange.shoppingImpact(before: calculate(plan, purchases), after: calculate(after.plan, after.purchases))
        return PlanChangePreview(change: change, householdID: family.id, source: source, destination: destination, lines: lines)
    }

    @MainActor
    static func applyPlanChange(_ preview: PlanChangePreview, household: HouseholdStore) async throws {
        guard preview.householdID == household.household?.id, !household.saving,
              preview.source.date >= BerlinDay.today() else { throw planChanged }
        switch preview.change {
        case let .out(slot):
            let changes: JSONObject = ["status": .string(PlanStatus.cancelled.rawValue),
                                       "note": .string(preview.source.note ?? "Auswärts essen")]
            guard await household.saveMeal(at: slot, changes: changes, condition: .unchanged(preview.source, includingDetails: true)) else {
                if let error = household.error {
                    household.error = nil
                    throw AssistantFailure.message(error)
                }
                throw planChanged
            }
        case let .move(from, target):
            if household.isDemo {
                let source = household.plan.first { $0.slot == from }
                let destination = household.plan.first { $0.slot == target }
                guard source?.planningSnapshot == preview.source.planningSnapshot,
                      destination?.planningSnapshot == preview.destination?.planningSnapshot,
                      household.applyDemoPlanChange(preview.change) else { throw planChanged }
            } else {
                let params: JSONObject = ["p_household": .string(preview.householdID),
                                          "p_from_date": .string(from.date), "p_from_meal": .string(from.meal.rawValue),
                                          "p_to_date": .string(target.date), "p_to_meal": .string(target.meal.rawValue),
                                          "p_expected_source": preview.source.planningSnapshot,
                                          "p_expected_target": preview.destination?.planningSnapshot ?? .null]
                do {
                    try await Backend.client.rpc("ep_plan_move_checked", params: params).execute()
                } catch let error as PostgrestError where error.code == "PT409" {
                    throw planChanged
                }
                if let start = household.weekStart { await household.loadWeek(from: start) }
            }
        }
    }

    private static func required(_ field: String, in input: JSONObject) throws -> String {
        guard let text = input[field]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { throw invalid }
        return text
    }

    private static func slot(_ input: JSONObject) throws -> MealSlot {
        let day = try required("datum", in: input)
        guard let date = BerlinDay.date(for: day), BerlinDay.key(for: date) == day,
              let meal = Meal(rawValue: try required("mahlzeit", in: input)) else { throw invalid }
        return MealSlot(date: day, meal: meal)
    }

    private static func destination(_ input: JSONObject, from: MealSlot) throws -> MealSlot {
        let destination = try slot(["datum": input["ziel_datum"] ?? .null,
                                    "mahlzeit": input["ziel_mahlzeit"]?.stringValue.map(AnyJSON.string) ?? .string(from.meal.rawValue)])
        guard destination != from, destination.date >= BerlinDay.today() else { throw invalid }
        return destination
    }

    private static func list(_ input: JSONObject) throws -> [JSONObject] {
        guard let items = input["eintraege"]?.arrayValue, (1...14).contains(items.count) else { throw invalid }
        return try items.map {
            guard let entry = $0.objectValue else { throw invalid }
            return entry
        }
    }

    private static func planItems(_ tool: AssistantTool, _ input: JSONObject) throws -> [PlanItem] {
        let inputs = tool == .batch ? try list(input) : [input]
        let items = try inputs.map {
            PlanItem(slot: try slot($0), recipeID: try required("rezept_id", in: $0), reason: $0["begruendung"]?.stringValue)
        }
        guard Set(items.map(\.slot)).count == items.count,
              items.allSatisfy({ $0.slot.date >= BerlinDay.today() }) else { throw invalid }
        return items
    }

    @MainActor
    private static func attendance(_ input: JSONObject, household: HouseholdStore) throws -> (MealSlot, Member, AttendanceStatus) {
        let name = try required("person", in: input)
        let members = household.members.filter {
            $0.name.localizedStandardCompare(name) == .orderedSame ||
                $0.name.split(separator: " ").first.map { String($0).localizedStandardCompare(name) == .orderedSame } == true
        }
        guard members.count == 1, let member = members.first,
              let status = AttendanceStatus(rawValue: try required("status", in: input)) else { throw invalid }
        return (try slot(input), member, status)
    }

    @MainActor
    private static func findRecipe(_ id: String, household: HouseholdStore) throws -> Recipe {
        guard let recipe = household.recipes.first(where: { $0.id == id }) else { throw invalid }
        return recipe
    }

    @MainActor
    private static func entries(_ slots: [MealSlot], household: HouseholdStore, includingEmpty: Bool = false) async throws -> [MealPlanEntry] {
        guard let family = household.household else { throw invalid }
        let rows: [MealPlanEntry]
        if household.isDemo {
            rows = household.plan
        } else {
            rows = try await Backend.client.from("ep_meal_plan").select().eq("household_id", value: family.id)
                .in("date", values: Array(Set(slots.map(\.date)))).execute().value
        }
        return rows.filter { slots.contains($0.slot) && (includingEmpty || $0.recipeID != nil || $0.leftoverOf != nil || $0.note != nil) }
    }

    private static func parseChange(_ input: JSONObject) throws -> PlanChange {
        let source = try slot(input)
        switch try required("aktion", in: input) {
        case "auswaerts": return .out(source)
        case "verschieben": return .move(source, try destination(input, from: source))
        default: throw invalid
        }
    }

    @MainActor
    private static func entryTitle(_ entry: MealPlanEntry, household: HouseholdStore) -> String {
        household.recipes.first(where: { $0.id == entry.recipeID })?.title ?? (entry.leftoverOf != nil ? "Reste" : entry.note ?? "Gericht")
    }

    private static func slotLabel(_ slot: MealSlot) -> String {
        guard let date = BerlinDay.date(for: slot.date) else { return slot.meal.label }
        var style = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "de_DE"))
        style.timeZone = BerlinDay.calendar.timeZone
        return date.formatted(style) + " · " + slot.meal.label
    }
}
