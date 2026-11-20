import Foundation
import GnocchiCore
import Observation
import Supabase

struct Membership: Decodable, Identifiable, Sendable {
    let householdID: String
    var name: String
    let memberID: String
    let active: Bool

    var id: String { householdID }

    enum CodingKeys: String, CodingKey {
        case householdID = "household_id"
        case name = "household_name"
        case memberID = "member_id"
        case active
    }
}

struct Recipe: Decodable, Identifiable, Sendable {
    struct Ingredient: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let amountText: String?
        let amount: Double?
        let unit: String?
        let group: String?
        let aisle: String?
        let position: Int

        enum CodingKeys: String, CodingKey {
            case id, name, position, amount, unit, aisle
            case amountText = "amount_text"
            case group = "group_name"
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            name = try values.decode(String.self, forKey: .name)
            position = try values.decode(Int.self, forKey: .position)
            amountText = try values.decodeIfPresent(String.self, forKey: .amountText)
            unit = try values.decodeIfPresent(String.self, forKey: .unit)
            group = try values.decodeIfPresent(String.self, forKey: .group)
            aisle = try values.decodeIfPresent(String.self, forKey: .aisle)
            amount = (try? values.decode(Double.self, forKey: .amount))
                ?? (try? values.decode(String.self, forKey: .amount)).flatMap(Double.init)
        }

        var shoppingIngredient: ShoppingIngredient {
            ShoppingIngredient(name: name, quantity: amount.map { Quantity(amount: $0, unit: unit) }, aisle: aisle)
        }

        func amountLabel(factor: Double?) -> String {
            guard let amount, let factor else { return amountText ?? "" }
            let original = Quantity(amount: amount, unit: unit)
            return original.scaled(by: factor).displayText(originalText: amountText, original: original)
        }
    }

    let id: String
    let title: String
    let subtitle: String?
    let imagePath: String?
    let timeText: String?
    let servings: Int?
    let steps: [String]
    var ingredients: [Ingredient]
    let publicSlug: String
    var cookbookID: String?
    var cookbookPage: Int?
    var source: String? = nil
    var categories: [String]? = nil
    var tags: [String]? = nil
    var folderID: String? = nil
    var diet: String? = nil
    var timeMin: Int? = nil
    var servingsText: String? = nil
    var tip: String? = nil
    var bookConfirmed: Bool? = nil
    var updatedAt: String? = nil
    var createdAt: String? = nil
    var nutrition: [String: String]? = nil
    var nutritionEstimated: Bool? = nil
    var extraMetadata: AnyJSON? = nil

    var pricePerServingCents: Int? {
        let value = extraMetadata?.objectValue?["price_per_serving_cents"]
        let cents = value?.intValue
        return cents.flatMap { (0...FoodMoney.maxCents).contains($0) ? $0 : nil }
    }

    var priceIsEstimate: Bool { extraMetadata?.objectValue?["price_is_estimate"]?.boolValue ?? false }

    var ingredientEmojiAliases: [String: [String]] {
        (extraMetadata?.objectValue?["ingredient_emoji_aliases"]?.objectValue ?? [:]).mapValues {
            ($0.arrayValue ?? []).compactMap(\.stringValue)
        }
    }

    var markdownMetadata: [RecipeMarkdown.Metadata] {
        (extraMetadata?.objectValue?["lines"]?.arrayValue ?? []).compactMap { entry in
            guard let line = entry.objectValue, let key = line["key"]?.stringValue,
                  let value = line["value"]?.stringValue, let location = line["where"]?.stringValue,
                  let position = RecipeMarkdown.Metadata.Position(rawValue: location) else { return nil }
            return RecipeMarkdown.Metadata(key: key, value: value, position: position)
        }
    }

    var photoCredit: RecipePhotoCredit? { RecipePhotoCredit.credit(title: title, imagePath: imagePath) }

    var imageURL: URL? {
        let path = imagePath.flatMap { $0.isEmpty ? nil : $0 } ?? photoCredit?.src
#if DEBUG
        if publicSlug == "demo", let path, path.hasPrefix("/images/rezepte/"),
           let local = Bundle.main.url(forResource: URL(fileURLWithPath: path).lastPathComponent,
                                       withExtension: nil, subdirectory: "rezepte") {
            return local
        }
#endif
        return path.flatMap { URL(string: $0, relativeTo: Backend.site)?.absoluteURL }
    }

    var shoppingRecipe: ShoppingRecipe {
        ShoppingRecipe(title: title, servings: servings, ingredients: ingredients.map(\.shoppingIngredient))
    }

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, servings, steps, source, categories, tags, diet, tip, nutrition
        case imagePath = "image_url"
        case timeText = "time_text"
        case ingredients = "ep_recipe_ingredients"
        case publicSlug = "public_slug"
        case cookbookID = "cookbook_id"
        case cookbookPage = "cookbook_page"
        case folderID = "folder_id"
        case timeMin = "time_min"
        case servingsText = "servings_text"
        case bookConfirmed = "cookbook_link_confirmed"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case nutritionEstimated = "nutrition_estimated"
        case extraMetadata = "extra_meta"
    }
}

struct RecipeFolder: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let emoji: String?

    var label: String { [emoji, name].compactMap { $0 }.joined(separator: " ") }
}

struct Cookbook: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let authors: [String]
    let publisher: String?
    let year: Int?
    let isbn: String?
    let coverPath: String?
    let notes: String?

    var coverURL: URL? {
        coverPath.flatMap { URL(string: $0, relativeTo: Backend.site)?.absoluteURL }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, authors, publisher, year, isbn, notes
        case coverPath = "cover_url"
    }

    var fields: JSONObject {
        [
            "title": .string(title), "authors": .array(authors.map(AnyJSON.string)),
            "publisher": publisher.map(AnyJSON.string) ?? .null, "year": year.map(AnyJSON.integer) ?? .null,
            "isbn": isbn.map(AnyJSON.string) ?? .null, "cover_url": coverPath.map(AnyJSON.string) ?? .null,
            "notes": notes.map(AnyJSON.string) ?? .null
        ]
    }
}

enum CookbookError: LocalizedError {
    case duplicateISBN, linkChanged

    var errorDescription: String? {
        switch self {
        case .duplicateISBN: "Diese ISBN steht schon im Regal."
        case .linkChanged: "Die Kochbuch-Verknüpfung wurde inzwischen geändert. Öffne das Rezept erneut."
        }
    }
}

@MainActor
@Observable
final class HouseholdStore {
    private struct FamilyDetails: Decodable, Sendable { let invite_code: String? }
    private let client: SupabaseClient
    private(set) var memberships: [Membership] = []
    private(set) var household: Membership?
    private(set) var members: [Member] = []
    private(set) var inviteCode: String?
    private(set) var recipes: [Recipe] = []
    private(set) var cookbooks: [Cookbook] = []
    private(set) var folders: [RecipeFolder] = []
    private(set) var cookingHistory: [CookingRecord] = []
    private(set) var recipeNotes: [String: [RecipeNote]] = [:]
    private var demoRatings: [String: [RecipeRating]] = [:]
    private var weeklyBudgets: [String: Int] = [:]
    private var budgetRequest = UUID()
    private var noteRequests: [String: UUID] = [:]
    private var historyRequest = UUID()
    @ObservationIgnored private var pendingDirectCooking: Set<DirectCooking> = []
    private(set) var plan: [MealPlanEntry] = []
    private var externalLeftovers: [MealPlanEntry] = []
    private var externalLeftoverSources: [MealPlanEntry] = []
    private(set) var attendance: [Attendance] = []
    private(set) var weekStart: String?
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var loadAttempted = false
    private(set) var saving = false
    var error: String?
    private var requestID = UUID()
    private(set) var isDemo = false

    init(client: SupabaseClient = Backend.client) {
        self.client = client
    }

    private struct DirectCooking: Hashable {
        let householdID: String
        let recipeID: String
        let day: String
    }

    func load() async {
        guard !isDemo else { return }
        let request = UUID()
        let initialRecipeIDs = Set(recipes.map(\.id))
        requestID = request
        loading = true
        defer {
            if request == requestID {
                loading = false
                loadAttempted = true
            }
        }
        do {
            let list: [Membership] = try await client.rpc("ep_my_memberships").execute().value
            guard let active = list.first(where: \.active) ?? list.first else {
                guard request == requestID, !Task.isCancelled else { return }
                memberships = list
                household = nil
                members = []
                inviteCode = nil
                recipes = []
                cookbooks = []
                folders = []
                cookingHistory = []
                recipeNotes = [:]
                noteRequests = [:]
                plan = []
                externalLeftoverSources = []
                externalLeftovers = []
                attendance = []
                weekStart = nil
                loaded = true
                return
            }
            async let family: [Member] = client.from("ep_members").select("id,name,avatar_url,default_week,email,user_id,role")
                .eq("household_id", value: active.id).order("position").execute().value
            async let collection = loadRecipes(householdID: active.id)
            async let books: [Cookbook] = client.from("ep_cookbooks").select()
                .eq("household_id", value: active.id).order("title").execute().value
            async let groups: [RecipeFolder] = client.from("ep_recipe_folders").select("id,name,emoji")
                .eq("household_id", value: active.id).order("position").order("name").execute().value
            async let details: FamilyDetails = client.from("ep_households").select("invite_code")
                .eq("id", value: active.id).single().execute().value
            let (people, entries, shelf, recipeFolders, familyDetails) = try await (family, collection, books, groups, details)
            guard request == requestID, !Task.isCancelled else { return }
            let sameHousehold = household?.id == active.id
            let fetchedIDs = Set(entries.map(\.id))
            // A week refresh may have found a new recipe after the collection request began.
            let discovered = sameHousehold
                ? recipes.filter { !initialRecipeIDs.contains($0.id) && !fetchedIDs.contains($0.id) }
                : []
            if !sameHousehold {
                cookingHistory = []
                recipeNotes = [:]
                noteRequests = [:]
                plan = []
                externalLeftoverSources = []
                externalLeftovers = []
                attendance = []
                weekStart = nil
            }
            memberships = list
            household = active
            members = people
            inviteCode = familyDetails.invite_code
            recipes = entries
            appendWeekRecipes(discovered)
            cookbooks = shelf
            folders = recipeFolders
            loaded = true
        } catch {
            guard request == requestID, !Task.isCancelled else { return }
            self.error = "Die Familie konnte nicht geladen werden."
        }
    }

    func loadWeek(from start: String, reportFailure: Bool = true) async {
        if isDemo {
            weekStart = start
            return
        }
        guard let family = household, !saving, !Task.isCancelled else { return }
        let request = UUID()
        weekRequest = request
        let end = BerlinDay.adding(6, to: start)
        do {
            async let dishes: [MealPlanEntry] = client.from("ep_meal_plan").select()
                .eq("household_id", value: family.id).gte("date", value: start)
                .lte("date", value: end).execute().value
            let people = members.map(\.id)
            let presence: [Attendance] = if people.isEmpty {
                []
            } else {
                try await client.from("ep_attendance").select().in("member_id", values: people)
                    .gte("date", value: start).lte("date", value: end).execute().value
            }
            let entries = try await dishes
            let missingSources = Set(entries.compactMap(\.leftoverOf)).subtracting(entries.map(\.id))
            let sources: [MealPlanEntry] = if missingSources.isEmpty {
                []
            } else {
                try await client.from("ep_meal_plan").select().eq("household_id", value: family.id)
                    .in("id", values: Array(missingSources)).execute().value
            }
            let sourceIDs = entries.filter { $0.recipeID != nil && $0.leftoverOf == nil }.map(\.id)
            let leftovers: [MealPlanEntry] = if sourceIDs.isEmpty {
                []
            } else {
                (try? await client.from("ep_meal_plan").select().eq("household_id", value: family.id)
                    .in("leftover_of", values: sourceIDs).gt("date", value: end).execute().value) ?? []
            }
            let lastLeftover = leftovers.map(\.date).max() ?? end
            let futureAttendance: [Attendance] = if people.isEmpty || lastLeftover <= end {
                []
            } else {
                (try? await client.from("ep_attendance").select().in("member_id", values: people)
                    .gt("date", value: end).lte("date", value: lastLeftover).execute().value) ?? []
            }
            guard weekRequest == request, household?.id == family.id, !Task.isCancelled else { return }
            let referenced = Set((entries + sources).compactMap(\.recipeID))
            let missing = referenced.subtracting(recipes.map(\.id))
            let discovered: [Recipe] = if missing.isEmpty {
                []
            } else {
                (try? await client.from("ep_recipes").select(Self.recipeSelection)
                    .eq("household_id", value: family.id).in("id", values: missing.sorted()).execute().value) ?? []
            }
            guard weekRequest == request, household?.id == family.id, !Task.isCancelled else { return }
            appendWeekRecipes(discovered)
            plan = entries
            externalLeftoverSources = sources
            externalLeftovers = leftovers
            attendance = presence + futureAttendance
            weekStart = start
        } catch {
            guard weekRequest == request, household?.id == family.id, !Task.isCancelled else { return }
            if reportFailure { self.error = "Die Woche konnte nicht geladen werden." }
        }
    }

    private var weekRequest = UUID()

    private func appendWeekRecipes(_ found: [Recipe]) {
        let existing = Set(recipes.map(\.id))
        let additions = found.filter { !existing.contains($0.id) }
        guard !additions.isEmpty else { return }
        recipes.append(contentsOf: additions)
        recipes.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func setDemoShoppingMarker(mealIDs: Set<String>, timestamp: String?) {
        guard isDemo else { return }
        for index in plan.indices where mealIDs.contains(plan[index].id) {
            let entry = plan[index]
            plan[index] = MealPlanEntry(id: entry.id, date: entry.date, meal: entry.meal, recipeID: entry.recipeID,
                                        leftoverOf: entry.leftoverOf, cookID: entry.cookID, secondCookID: entry.secondCookID,
                                        servingsOverride: entry.servingsOverride, status: entry.status,
                                        note: entry.note, shoppedAt: timestamp, familyGuests: entry.familyGuests)
        }
    }

    var planIncludingLaterLeftovers: [MealPlanEntry] { plan + externalLeftovers }

    func isMealPrepSource(_ id: String) -> Bool {
        planIncludingLaterLeftovers.contains { $0.leftoverOf == id && $0.status != .cancelled }
    }

    func leftoverSource(_ id: String?) -> MealPlanEntry? {
        guard let id else { return nil }
        return plan.first { $0.id == id } ?? externalLeftoverSources.first { $0.id == id }
    }

    func recipeForMeal(recipeID: String?, leftoverOf: String?) -> Recipe? {
        guard let id = recipeID ?? leftoverSource(leftoverOf)?.recipeID else { return nil }
        return recipes.first { $0.id == id }
    }

    func watchWeek(from start: String) async {
        await loadWeek(from: start)
        guard !isDemo, let family = household else { return }
        await Backend.watchChanges(using: client, household: family.id,
                                   tables: ["ep_meal_plan", "ep_attendance"]) {
            guard self.household?.id == family.id else { return }
            await self.loadWeek(from: start, reportFailure: false)
        }
    }

    func switchHousehold(to id: String) async {
        guard !saving, id != household?.id else { return }
        await changeHousehold(using: "ep_switch_household", params: ["p_household": id])
    }

    func createHousehold(name: String, memberName: String) async {
        #if DEBUG
        if isDemo, household == nil {
            let member = Member(id: "demo-owner", name: memberName, hasLogin: true, isAdmin: true)
            let membership = Membership(householdID: "demo", name: name, memberID: member.id, active: true)
            members = [member]
            memberships = [membership]
            inviteCode = "DEMO2026"
            household = membership
            return
        }
        #endif
        await changeHousehold(using: "ep_create_household", params: ["p_name": name, "p_member_name": memberName])
    }

    func joinHousehold(code: String, memberName: String) async {
        await changeHousehold(using: "ep_join_household", params: ["p_code": code, "p_member_name": memberName])
    }

    private func changeHousehold(using rpc: String, params: [String: String]) async {
        guard !saving, !isDemo else { return }
        saving = true
        do {
            try await client.rpc(rpc, params: params).execute()
            household = nil
            loaded = false
            saving = false
            await load()
        } catch {
            saving = false
            self.error = (error as? PostgrestError)?.message
                ?? "Die Änderung konnte nicht gespeichert werden. Prüfe deine Eingaben und versuche es erneut."
        }
    }

    func setAttendance(for member: Member, at slot: MealSlot, status: AttendanceStatus, guests: Int) async {
        guard !saving, guests >= 0, let family = household, members.contains(where: { $0.id == member.id }) else { return }
        if isDemo {
            attendance.removeAll { $0.memberID == member.id && $0.meal == slot.meal && $0.date == slot.date }
            attendance.append(Attendance(id: UUID().uuidString, memberID: member.id, date: slot.date,
                                         meal: slot.meal, status: status, guests: status == .present ? guests : 0))
            return
        }
        saving = true
        weekRequest = UUID()
        struct Payload: Encodable {
            let member_id: String
            let date: String
            let meal: Meal
            let status: AttendanceStatus
            let guests: Int
        }
        do {
            let row: Attendance = try await client.from("ep_attendance")
                .upsert(Payload(member_id: member.id, date: slot.date, meal: slot.meal, status: status,
                                guests: status == .present ? guests : 0),
                        onConflict: "member_id,date,meal")
                .select().single().execute().value
            if household?.id == family.id {
                attendance.removeAll { $0.memberID == member.id && $0.meal == slot.meal && $0.date == slot.date }
                attendance.append(row)
            }
        } catch {
            if household?.id == family.id { self.error = "Die Anwesenheit konnte nicht gespeichert werden." }
        }
        saving = false
        if household?.id == family.id, let weekStart { await loadWeek(from: weekStart) }
    }

    enum MealWriteCondition {
        case always
        case unplanned
        case unchanged(MealPlanEntry?, includingDetails: Bool = false)

        fileprivate func matches(_ current: MealPlanEntry?) -> Bool {
            switch self {
            case .always: true
            case .unplanned: current?.allowsSuggestion ?? true
            case let .unchanged(expected, includingDetails):
                current?.snapshot(includingDetails: includingDetails) == expected?.snapshot(includingDetails: includingDetails)
            }
        }
    }

    func scheduleRecipe(_ recipeID: String, at slot: MealSlot, expected: MealPlanEntry?) async -> Bool {
        var changes: JSONObject = ["recipe_id": .string(recipeID)]
        if expected?.alreadyPlansRecipe(recipeID) != true {
            changes["leftover_of"] = .null
            changes["status"] = .string(PlanStatus.planned.rawValue)
            changes["shopped_at"] = .null
        }
        return await saveMeal(at: slot, changes: changes, condition: .unchanged(expected))
    }

    func saveMeal(at slot: MealSlot, changes: JSONObject, condition: MealWriteCondition = .always) async -> Bool {
        guard let family = household, !saving else { return false }
        guard !changes.isEmpty else { return true }
        saving = true
        weekRequest = UUID()
        var patch: [String: AnyJSON] = [
            "household_id": .string(family.id),
            "date": .string(slot.date),
            "meal": .string(slot.meal.rawValue)
        ]
        patch.merge(changes) { _, new in new }
        do {
            let saved: MealPlanEntry?
            if isDemo {
                let old = plan.first { $0.slot == slot }
                guard condition.matches(old) else {
                    saving = false
                    return false
                }
                var row: [String: AnyJSON] = [
                    "id": .string(old?.id ?? UUID().uuidString),
                    "status": .string((old?.status ?? .planned).rawValue)
                ]
                row["recipe_id"] = old?.recipeID.map(AnyJSON.string)
                row["leftover_of"] = old?.leftoverOf.map(AnyJSON.string)
                row["note"] = old?.note.map(AnyJSON.string)
                row["servings_override"] = old?.servingsOverride.map(AnyJSON.integer)
                row["family_guests"] = old?.familyGuests.map(AnyJSON.integer)
                row["cook_id"] = old?.cookID.map(AnyJSON.string)
                row["cook2_id"] = old?.secondCookID.map(AnyJSON.string)
                row["shopped_at"] = old?.shoppedAt.map(AnyJSON.string)
                row.merge(patch) { _, new in new }
                if slot.date < BerlinDay.today(), row["status"] == .string(PlanStatus.planned.rawValue),
                   row["recipe_id"]?.stringValue != nil, row["leftover_of"]?.stringValue == nil {
                    row["status"] = .string(PlanStatus.cooked.rawValue)
                }
                let entry = try JSONDecoder().decode(MealPlanEntry.self, from: JSONEncoder().encode(row))
                updateDemoCookingHistory(for: entry)
                saved = entry
            } else {
                switch condition {
                case .always:
                    saved = try await client.from("ep_meal_plan")
                        .upsert(patch, onConflict: "household_id,date,meal").select().single().execute().value
                case .unplanned:
                    saved = try await fillUnplannedMeal(at: slot, householdID: family.id, insert: patch, changes: changes)
                case .unchanged(nil, _):
                    saved = try await insertMealIfFree(patch)
                case let .unchanged(expected?, includingDetails):
                    saved = try await updateMeal(at: slot, householdID: family.id, expected: expected,
                                                 includingDetails: includingDetails, changes: changes)
                }
            }
            if let saved, household?.id == family.id {
                plan.removeAll { $0.slot == slot }
                plan.append(saved)
            }
            saving = false
            guard household?.id == family.id else { return false }
            if let weekStart { await loadWeek(from: weekStart) }
            return saved != nil && household?.id == family.id
        } catch {
            saving = false
            self.error = "Das Gericht konnte nicht gespeichert werden."
            return false
        }
    }

    private func fillUnplannedMeal(at slot: MealSlot, householdID: String, insert: JSONObject,
                                   changes: JSONObject) async throws -> MealPlanEntry? {
        if let meal = try await insertMealIfFree(insert) { return meal }

        // The unique slot and these filters let another client's entry win a concurrent write.
        let updated: [MealPlanEntry] = try await client.from("ep_meal_plan").update(changes)
            .eq("household_id", value: householdID).eq("date", value: slot.date).eq("meal", value: slot.meal.rawValue)
            .eq("status", value: PlanStatus.planned.rawValue)
            .is("recipe_id", value: nil).is("leftover_of", value: nil).or("note.is.null,note.eq.\"\"")
            .select().execute().value
        return updated.first
    }

    private func insertMealIfFree(_ fields: JSONObject) async throws -> MealPlanEntry? {
        let inserted: [MealPlanEntry] = try await client.from("ep_meal_plan")
            .upsert(fields, onConflict: "household_id,date,meal", ignoreDuplicates: true).select().execute().value
        return inserted.first
    }

    private func updateMeal(at slot: MealSlot, householdID: String, expected: MealPlanEntry,
                            includingDetails: Bool, changes: JSONObject) async throws -> MealPlanEntry? {
        let update = try client.from("ep_meal_plan").update(changes)
            .eq("household_id", value: householdID).eq("date", value: slot.date).eq("meal", value: slot.meal.rawValue)
            .eq("id", value: expected.id).eq("status", value: expected.status.rawValue)
        for (column, value) in expected.comparisonFields(includingDetails: includingDetails) {
            if let value {
                if column == "note", !value.isEmpty {
                    // A singleton list lets the SDK quote punctuation in free-text notes.
                    _ = update.in(column, values: [value])
                } else {
                    _ = update.eq(column, value: value)
                }
            } else {
                _ = update.is(column, value: nil)
            }
        }
        if changes["family_guests"] != nil {
            if let guests = expected.familyGuests { _ = update.eq("family_guests", value: guests) }
            else { _ = update.is("family_guests", value: nil) }
        }
        let updated: [MealPlanEntry] = try await update.select().execute().value
        return updated.first
    }

    func recordMealSuggestion(recipeID: String, slot: MealSlot) async {
        guard !isDemo, let family = household, let week = BerlinDay.isoWeek(slot.date),
              let recipe = recipes.first(where: { $0.id == recipeID }) else { return }
        let lastCooked = cookingHistory.filter { $0.recipe_id == recipeID }.map(\.cooked_on).max()
        let days = lastCooked.flatMap { MealSuggestion.daysSince($0, today: BerlinDay.today()) }
        let row = ["household_id": family.id, "iso_week": week, "recipe_id": recipeID,
                   "origin": recipe.cookbookID == nil ? "sammlung" : "regal", "generated_by": "regel",
                   "status": "angenommen", "reason_shown": days.map { "\($0) Tage nicht gekocht" } ?? "noch nie gekocht"]
        do {
            try await client.from("ep_suggestions").insert(row).execute()
        } catch {
            // The meal is already saved. A failed log must not retry the meal write.
        }
    }
}

extension MealPlanEntry {
    var allowsSuggestion: Bool {
        status == .planned && recipeID == nil && leftoverOf == nil && (note ?? "").isEmpty
    }

    func alreadyPlansRecipe(_ recipe: String?) -> Bool {
        recipe != nil && recipeID == recipe && status == .planned && leftoverOf == nil
    }

    fileprivate func comparisonFields(includingDetails: Bool) -> [(String, String?)] {
        let assignment = [("recipe_id", recipeID), ("leftover_of", leftoverOf), ("note", note), ("shopped_at", shoppedAt)]
        guard includingDetails else { return assignment }
        return assignment + [("cook_id", cookID), ("cook2_id", secondCookID), ("servings_override", servingsOverride.map(String.init))]
    }

    var schedulingSnapshot: AnyJSON { snapshot(includingDetails: false) }
    var planningSnapshot: AnyJSON { snapshot(includingDetails: true) }

    fileprivate func snapshot(includingDetails: Bool) -> AnyJSON {
        var fields: JSONObject = ["id": .string(id), "status": .string(status.rawValue)]
        if includingDetails { fields["family_guests"] = familyGuests.map(AnyJSON.integer) ?? .null }
        for (key, value) in comparisonFields(includingDetails: includingDetails) {
            fields[key] = value.map(AnyJSON.string) ?? .null
        }
        return .object(fields)
    }
}

extension HouseholdStore {
    func saveDemoRecipe(id: String, expectedRevision: String?, draft: RecipeDraft, replacingIngredients: Bool) throws {
        guard isDemo else { return }
        let previous = recipes.first { $0.id == id }
        if let expectedRevision {
            guard previous?.updatedAt == expectedRevision else { throw RecipeSaveFailure.stale }
        } else if previous != nil {
            return
        }
        var row = draft.recipeFields
        row["id"] = .string(id)
        row["public_slug"] = .string(previous?.publicSlug ?? "demo")
        row["updated_at"] = .string(UUID().uuidString)
        row["created_at"] = previous?.createdAt.map(AnyJSON.string)
        if row["nutrition"] == nil, let values = previous?.nutrition {
            row["nutrition"] = .object(values.mapValues(AnyJSON.string))
        }
        if row["nutrition_estimated"] == nil { row["nutrition_estimated"] = previous?.nutritionEstimated.map(AnyJSON.bool) }
        if row["extra_meta"] == nil { row["extra_meta"] = previous?.extraMetadata }
        row["ep_recipe_ingredients"] = .array((replacingIngredients ? draft.ingredientFields : []).enumerated().map { index, ingredient in
            var fields = ingredient.objectValue ?? [:]
            fields["id"] = .string(UUID().uuidString)
            fields["position"] = .integer(index)
            return .object(fields)
        })
        var recipe = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(row))
        if !replacingIngredients, let previous { recipe.ingredients = previous.ingredients }
        recipes.removeAll { $0.id == id }
        recipes.append(recipe)
        recipes.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static let recipeSelection = "*,ep_recipe_ingredients(id,name,amount,unit,amount_text,group_name,position,aisle)"

    private func loadRecipes(householdID: String) async throws -> [Recipe] {
        let pageSize = 500
        var recipes: [Recipe] = []
        while true {
            try Task.checkCancellation()
            let offset = recipes.count
            let page: [Recipe] = try await client.from("ep_recipes").select(Self.recipeSelection)
                .eq("household_id", value: householdID).order("title").order("id")
                .range(from: offset, to: offset + pageSize - 1).execute().value
            recipes.append(contentsOf: page)
            if page.count < pageSize { return recipes }
        }
    }

    func deleteRecipe(_ recipe: Recipe) async throws {
        guard let family = household, recipes.contains(where: { $0.id == recipe.id }) else {
            throw HouseholdEditError.unavailable
        }
        if !isDemo {
            try await client.from("ep_recipes").delete().eq("id", value: recipe.id)
                .eq("household_id", value: family.id).execute()
        }
        guard household?.id == family.id else { return }

        historyRequest = UUID()
        noteRequests[recipe.id] = nil
        recipes.removeAll { $0.id == recipe.id }
        recipeNotes[recipe.id] = nil
        cookingHistory.removeAll { $0.recipe_id == recipe.id }
        // Match ON DELETE SET NULL for existing meal slots.
        for index in plan.indices where plan[index].recipeID == recipe.id {
            let entry = plan[index]
            plan[index] = MealPlanEntry(id: entry.id, date: entry.date, meal: entry.meal,
                                        leftoverOf: entry.leftoverOf, cookID: entry.cookID,
                                        secondCookID: entry.secondCookID, servingsOverride: entry.servingsOverride,
                                        status: entry.status, note: entry.note, shoppedAt: entry.shoppedAt, familyGuests: entry.familyGuests)
        }
        if !isDemo {
            await load()
        }
    }

    func saveCookbook(_ book: Cookbook, existing: Bool) async throws {
        guard let family = household, !book.title.isEmpty else { throw HouseholdEditError.unavailable }
        let saved: Cookbook
        if isDemo {
            if let isbn = book.isbn, cookbooks.contains(where: { $0.id != book.id && $0.isbn == isbn }) {
                throw CookbookError.duplicateISBN
            }
            saved = book
        } else {
            do {
                if existing {
                    saved = try await client.from("ep_cookbooks").update(book.fields).eq("id", value: book.id)
                        .eq("household_id", value: family.id).select().single().execute().value
                } else {
                    let row = book.fields.merging(["id": .string(book.id), "household_id": .string(family.id)]) { value, _ in value }
                    try await client.from("ep_cookbooks").upsert(row, onConflict: "id", ignoreDuplicates: true).execute()
                    saved = try await client.from("ep_cookbooks").select().eq("id", value: book.id)
                        .eq("household_id", value: family.id).single().execute().value
                }
            } catch let error as PostgrestError where error.code == "23505" {
                throw CookbookError.duplicateISBN
            }
        }
        guard household?.id == family.id else { return }
        cookbooks.removeAll { $0.id == saved.id }
        cookbooks.append(saved)
        cookbooks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func removeCookbook(_ book: Cookbook) async throws {
        guard let family = household else { throw HouseholdEditError.unavailable }
        if !isDemo {
            try await client.from("ep_cookbooks").delete().eq("id", value: book.id)
                .eq("household_id", value: family.id).execute()
        }
        guard household?.id == family.id else { return }
        cookbooks.removeAll { $0.id == book.id }
        for index in recipes.indices where recipes[index].cookbookID == book.id {
            recipes[index].cookbookID = nil
        }
        if !isDemo { await load() }
    }

    func linkRecipe(_ recipe: Recipe, to book: Cookbook?, page: Int?, confirmed: Bool = true) async throws {
        guard let family = household, book.map({ selected in cookbooks.contains { $0.id == selected.id } }) ?? true,
              page.map({ book != nil && (1...Int(Int32.max)).contains($0) }) ?? true else { throw HouseholdEditError.unavailable }
        let updated: Recipe
        if isDemo {
            guard var current = recipes.first(where: { $0.id == recipe.id }) else { throw HouseholdEditError.unavailable }
            guard (current.cookbookID, current.cookbookPage, current.bookConfirmed) ==
                  (recipe.cookbookID, recipe.cookbookPage, recipe.bookConfirmed) else { throw CookbookError.linkChanged }
            current.cookbookID = book?.id
            current.cookbookPage = page
            current.bookConfirmed = confirmed
            current.updatedAt = UUID().uuidString
            updated = current
        } else {
            let fields: JSONObject = ["cookbook_id": book.map { .string($0.id) } ?? .null,
                                      "cookbook_page": page.map(AnyJSON.integer) ?? .null,
                                      "cookbook_link_confirmed": .bool(confirmed)]
            let query = try client.from("ep_recipes").update(fields).eq("id", value: recipe.id)
                .eq("household_id", value: family.id)
            let expected: [(String, String?)] = [
                ("cookbook_id", recipe.cookbookID), ("cookbook_page", recipe.cookbookPage.map(String.init)),
                ("cookbook_link_confirmed", recipe.bookConfirmed.map(String.init))
            ]
            for (column, value) in expected {
                if let value { _ = query.eq(column, value: value) }
                else { _ = query.is(column, value: nil) }
            }
            let rows: [Recipe] = try await query.select(Self.recipeSelection).execute().value
            guard let saved = rows.first else {
                await load()
                throw CookbookError.linkChanged
            }
            updated = saved
        }
        guard household?.id == family.id, let index = recipes.firstIndex(where: { $0.id == updated.id }) else { return }
        recipes[index] = updated
    }

    func organizeRecipe(id: String, folderID: String?, tags: [String]) async throws {
        guard let family = household, let index = recipes.firstIndex(where: { $0.id == id }),
              folderID == nil || folders.contains(where: { $0.id == folderID }) else {
            throw HouseholdEditError.unavailable
        }
        if isDemo {
            recipes[index].folderID = folderID
            recipes[index].tags = tags
            recipes[index].updatedAt = UUID().uuidString
            return
        }

        struct Organization: Decodable {
            let folder_id: String?
            let tags: [String]
            let updated_at: String
        }
        let fields: JSONObject = ["folder_id": folderID.map(AnyJSON.string) ?? .null,
                                  "tags": .array(tags.map(AnyJSON.string))]
        let updated: Organization = try await client.from("ep_recipes").update(fields).eq("id", value: id)
            .eq("household_id", value: family.id).select("folder_id,tags,updated_at").single().execute().value
        guard household?.id == family.id, let index = recipes.firstIndex(where: { $0.id == id }) else { return }
        recipes[index].folderID = updated.folder_id
        recipes[index].tags = updated.tags
        recipes[index].updatedAt = updated.updated_at
    }
}

#if DEBUG
extension HouseholdStore {
    static func demo(onboarding: Bool = false, includeSampleRecipes: Bool = false) -> HouseholdStore {
        let store = HouseholdStore()
        store.isDemo = true
        store.loaded = true
        if onboarding { return store }
        let family = Membership(householdID: "demo", name: "Familie Sommer", memberID: "lin", active: true)
        let today = BerlinDay.today()
        let ingredients = (try? JSONDecoder().decode([Recipe.Ingredient].self, from: Data("""
            [
                {"id":"gn","name":"Gnocchi","position":0,"amount":600,"unit":"g","amount_text":"600 g"},
                {"id":"to","name":"Tomaten","position":1,"amount":400,"unit":"g","amount_text":"400 g"},
                {"id":"ba","name":"Basilikum","position":2}
            ]
            """.utf8))) ?? []
        store.household = family
        store.memberships = [family]
        store.inviteCode = "DEMO2026"
        store.folders = [RecipeFolder(id: "schnell", name: "Schnelle Küche", emoji: "⚡️")]
        store.cookbooks = [
            Cookbook(id: "demo-italien", title: "Die echte italienische Küche", authors: [], publisher: nil,
                     year: nil, isbn: nil, coverPath: nil, notes: nil),
            Cookbook(id: "demo-jerusalem", title: "Jerusalem", authors: [], publisher: nil,
                     year: nil, isbn: nil, coverPath: nil, notes: nil)
        ]
        store.members = [Member(id: "lin", name: "Lin", hasLogin: true, isAdmin: true),
                         Member(id: "meli", name: "Meli", hasLogin: true), Member(id: "toni", name: "Toni")]
        store.recipes = [
            Recipe(id: "gnocchi", title: "Tomaten-Gnocchi mit Burrata", subtitle: "Mit Basilikum",
                   imagePath: "/images/rezepte/tomaten-gnocchi.jpg", timeText: "25 Minuten", servings: 4,
                   steps: ["Gnocchi in einer Pfanne goldbraun braten.", "Tomaten und Burrata dazugeben."],
                   ingredients: ingredients, publicSlug: "demo", cookbookID: nil, cookbookPage: nil),
            Recipe(id: "lachs", title: "Ofenlachs mit Gemüse", subtitle: nil,
                   imagePath: "/images/rezepte/ofenlachs.jpg", timeText: "35 Minuten", servings: 4,
                   steps: [], ingredients: [], publicSlug: "demo", cookbookID: nil, cookbookPage: nil)
        ]
        store.plan = [
            MealPlanEntry(id: "1", date: today, meal: .lunch, recipeID: "gnocchi", cookID: "lin"),
            MealPlanEntry(id: "2", date: today, meal: .dinner, recipeID: "lachs", cookID: "meli"),
            MealPlanEntry(id: "3", date: BerlinDay.adding(1, to: today), meal: .lunch, leftoverOf: "1")
        ]
        store.recipes[0].folderID = "schnell"
        store.recipes[0].cookbookID = "demo-italien"
        store.recipes[0].bookConfirmed = true
        store.recipes[0].updatedAt = UUID().uuidString
        store.recipes[1].updatedAt = UUID().uuidString
        store.recipes[0].tags = ["pasta"]
        store.recipes[0].diet = "vegetarisch"
        store.recipes[0].timeMin = 25
        if includeSampleRecipes {
            store.recipes[0].nutrition = ["kcal": "510", "Eiweiß": "18 g", "Fett": "20 g", "Kohlenhydrate": "63 g"]
            store.recipes[0].nutritionEstimated = true
            store.recipes[0].extraMetadata = .object(["price_per_serving_cents": .integer(310)])
            store.demoRatings["gnocchi"] = [RecipeRating(memberID: "meli", stars: 5)]
            store.weeklyBudgets[family.id] = 8_000
        }
        store.recipes[1].diet = "fisch"
        store.recipes[1].timeMin = 35
        store.cookingHistory = [CookingRecord(id: "demo-cooked", recipe_id: "lachs",
                                             cooked_on: BerlinDay.adding(-35, to: today), meal_plan_id: nil,
                                             cook_id: "lin", servings: 3, source: .backdated)]
        let timestamp = Date.now.ISO8601Format()
        store.recipeNotes["gnocchi"] = [
            RecipeNote(id: "demo-note", member_id: "meli", body: "Burrata erst beim Servieren dazugeben.",
                       created_at: timestamp, updated_at: timestamp)
        ]
        if includeSampleRecipes {
            store.plan.append(MealPlanEntry(id: "demo-yesterday", date: BerlinDay.adding(-1, to: today),
                                            meal: .dinner, recipeID: "lachs", cookID: "meli", status: .cooked))
            store.addDemoSamples(today: today)
        }
        return store
    }

    private func addDemoSamples(today: String) {
        guard let url = Bundle.main.url(forResource: "rezeptsammlung", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8),
              let collection = try? RecipeMarkdown.parseCollection(markdown) else { return }
        let samples: [(id: String, title: String)] = [
            ("spinatquiche", "Spinatquiche mit Feta"),
            ("teriyaki", "Teriyaki Hähnchen"),
            ("cajun-pasta", "Cajun Chicken Pasta"),
            ("reisbandnudel-suppe", "Asiatische Reisbandnudel-Suppe"),
            ("sommerrollen", "Sommerrollen (Vietnamesisch)"),
            ("wraps", "Wraps Louisa"),
            ("chili", "Chili con Carne"),
            ("honighaehnchen", "Honighähnchen")
        ]
        for sample in samples {
            guard let recipe = collection.first(where: { $0.title == sample.title }) else { continue }
            let draft = ImportedRecipe(markdown: recipe).draft(books: cookbooks)
            try? saveDemoRecipe(id: sample.id, expectedRevision: nil, draft: draft, replacingIngredients: true)
        }

        let scheduled: [(recipe: String, day: Int, meal: Meal, cook: String)] = [
            ("teriyaki", 1, .dinner, "meli"),
            ("spinatquiche", 2, .lunch, "lin"),
            ("sommerrollen", 3, .dinner, "toni"),
            ("reisbandnudel-suppe", 4, .dinner, "lin"),
            ("chili", 6, .dinner, "meli")
        ]
        for sample in scheduled where recipes.contains(where: { $0.id == sample.recipe }) {
            plan.append(MealPlanEntry(id: "demo-meal-\(sample.recipe)", date: BerlinDay.adding(sample.day, to: today),
                                      meal: sample.meal, recipeID: sample.recipe, cookID: sample.cook))
        }
    }
}
#endif

extension HouseholdStore {
    func applyDemoPlanChange(_ change: PlanChange) -> Bool {
        guard isDemo, let changed = change.applying(to: plan, purchases: [], today: BerlinDay.today()) else { return false }
        plan = changed.plan
        var affected = Set([change.source])
        if case let .move(_, target) = change { affected.insert(target) }
        for entry in plan where affected.contains(entry.slot) { updateDemoCookingHistory(for: entry) }
        return true
    }

    func plannedMeals(from start: String, through end: String) async throws -> [MealPlanEntry] {
        guard let family = household else { throw HouseholdEditError.unavailable }
        if isDemo {
            return plan.filter { $0.date >= start && $0.date <= end }
        }
        let entries: [MealPlanEntry] = try await client.from("ep_meal_plan").select()
            .eq("household_id", value: family.id).gte("date", value: start).lte("date", value: end)
            .execute().value
        guard household?.id == family.id else { throw HouseholdEditError.unavailable }
        return entries
    }

}

struct InvitePreview: Decodable, Sendable {
    let household_name: String
    let member_count: Int
    let already_member: Bool
}

enum HouseholdEditError: LocalizedError {
    case unavailable
    case passwordPending
    var errorDescription: String? {
        switch self {
        case .unavailable: "Diese Änderung ist gerade nicht möglich."
        case .passwordPending: "Das Mitglied wurde gespeichert. Das Passwort konnte nicht gesetzt werden. Du kannst es erneut versuchen."
        }
    }
}

extension HouseholdStore {
    var isAdmin: Bool {
        members.first { $0.id == household?.memberID }?.isAdmin == true
    }

    var cookCounts: [String: Int] {
        let since = BerlinDay.adding(-28, to: BerlinDay.today())
        return cookingHistory.reduce(into: [:]) { counts, record in
            if let cook = record.cook_id, record.cooked_on >= since { counts[cook, default: 0] += 1 }
        }
    }

    func lookupInvite(_ code: String) async throws -> InvitePreview? {
        guard !isDemo else { return nil }
        let matches: [InvitePreview] = try await client.rpc("ep_invite_preview", params: ["p_code": code]).execute().value
        return matches.first
    }

    func regenerateInvite() async throws {
        guard isAdmin, let family = household else { throw HouseholdEditError.unavailable }
        if isDemo {
            inviteCode = String(UUID().uuidString.prefix(8)).uppercased()
        } else {
            let code: String = try await client.rpc("ep_regenerate_invite", params: ["p_household": family.id]).execute().value
            if household?.id == family.id { inviteCode = code }
        }
    }

    func renameFamily(_ name: String) async throws {
        guard isAdmin, let family = household else { throw HouseholdEditError.unavailable }
        if !isDemo {
            try await client.from("ep_households").update(["name": name]).eq("id", value: family.id)
                .select("id").single().execute()
        }
        guard household?.id == family.id else { return }
        household?.name = name
        if let index = memberships.firstIndex(where: { $0.id == family.id }) { memberships[index].name = name }
    }

    func leaveFamily() async {
        guard let family = household else { return }
        await changeHousehold(using: "ep_leave_household", params: ["p_household": family.id])
    }

    func saveStandardWeek(_ week: [String: [Meal: AttendanceStatus]], memberID: String) async throws {
        guard let family = household, let member = members.first(where: { $0.id == memberID }) else {
            throw HouseholdEditError.unavailable
        }
        let replacement: Member
        if isDemo {
            replacement = Member(id: member.id, name: member.name, avatarURL: member.avatarURL, defaultWeek: week,
                                 email: member.email, hasLogin: member.hasLogin, isAdmin: member.isAdmin)
        } else {
            let payload = week.mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.rawValue, $0.value.rawValue) }) }
            replacement = try await client.from("ep_members").update(["default_week": payload])
                .eq("id", value: memberID).eq("household_id", value: family.id).select().single().execute().value
        }
        guard household?.id == family.id, let index = members.firstIndex(where: { $0.id == memberID }) else { return }
        members[index] = replacement
    }

    func saveMember(id: String, existing: Bool, name: String, email: String, admin: Bool) async throws {
        guard isAdmin, let family = household, !(id == family.memberID && !admin) else {
            throw HouseholdEditError.unavailable
        }
        let saved: Member
        if isDemo {
            let previous = members.first { $0.id == id }
            saved = Member(id: id, name: name, avatarURL: previous?.avatarURL, defaultWeek: previous?.defaultWeek ?? [:],
                           email: email.isEmpty ? nil : email, hasLogin: previous?.hasLogin ?? false, isAdmin: admin)
        } else {
            var fields: JSONObject = ["name": .string(name), "email": email.isEmpty ? .null : .string(email),
                                       "role": .string(admin ? "admin" : "member")]
            if existing {
                saved = try await client.from("ep_members").update(fields).eq("id", value: id)
                    .eq("household_id", value: family.id).select().single().execute().value
            } else {
                fields["id"] = .string(id)
                fields["household_id"] = .string(family.id)
                fields["position"] = .integer(members.count)
                try await client.from("ep_members").upsert(fields, onConflict: "id", ignoreDuplicates: true).execute()
                saved = try await client.from("ep_members").select().eq("id", value: id)
                    .eq("household_id", value: family.id).single().execute().value
            }
        }
        guard household?.id == family.id else { return }
        if let index = members.firstIndex(where: { $0.id == id }) { members[index] = saved }
        else { members.append(saved) }
    }

    func setMemberPassword(_ password: String, memberID: String) async throws {
        guard isAdmin, !isDemo, members.contains(where: { $0.id == memberID }) else {
            throw HouseholdEditError.unavailable
        }
        do {
            try await client.rpc("ep_admin_set_password", params: ["p_member": memberID, "p_password": password]).execute()
            await load()
        } catch {
            throw HouseholdEditError.passwordPending
        }
    }

    func saveMemberPhoto(_ jpeg: Data?, memberID: String) async throws {
        guard !isDemo, let family = household, isAdmin || memberID == family.memberID,
              members.contains(where: { $0.id == memberID }) else { throw HouseholdEditError.unavailable }
        let bucket = client.storage.from("ep-images")
        let path = "\(family.id)/avatars/\(UUID().uuidString).jpg"
        let imageURL: String?
        if let jpeg {
            imageURL = try bucket.getPublicURL(path: path).absoluteString
            try await bucket.upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        } else {
            imageURL = nil
        }
        let patch: JSONObject = ["avatar_url": imageURL.map(AnyJSON.string) ?? .null]
        let updated: Member = try await client.from("ep_members").update(patch)
            .eq("id", value: memberID).eq("household_id", value: family.id).select().single().execute().value
        guard household?.id == family.id, let index = members.firstIndex(where: { $0.id == memberID }) else { return }
        members[index] = updated
    }
}

struct CookingRecord: Decodable, Identifiable, Sendable {
    enum Source: String, Decodable, Sendable {
        case plan
        case manual = "manuell"
        case backdated = "nachgetragen"

        var label: String {
            switch self {
            case .plan: "Aus dem Wochenplan"
            case .manual: "Außerhalb des Plans"
            case .backdated: "Nachgetragen"
            }
        }
    }

    let id: String
    let recipe_id: String
    let cooked_on: String
    let meal_plan_id: String?
    let cook_id: String?
    let servings: Int?
    let source: Source
    var meal: Meal? = nil

    private var localMealKey: String { "ep.historyMeal.\(id)" }

    mutating func loadLocalMeal() {
        guard meal == nil else { return }
        meal = UserDefaults.standard.string(forKey: localMealKey).flatMap(Meal.init(rawValue:))
    }

    mutating func setLocalMeal(_ meal: Meal?) {
        self.meal = meal
        UserDefaults.standard.set(meal?.rawValue, forKey: localMealKey)
    }
}

struct RecipeNote: Decodable, Identifiable, Sendable {
    let id: String
    let member_id: String?
    var body: String
    let created_at: String
    var updated_at: String

    var createdAt: Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(created_at))
            ?? (try? Date.ISO8601FormatStyle().parse(created_at))
    }
}

enum RecipeNoteError: LocalizedError {
    case invalidBody

    var errorDescription: String? { "Eine Notiz muss zwischen 1 und 4000 Zeichen haben." }
}

extension HouseholdStore {
    func canEditNote(_ note: RecipeNote) -> Bool {
        guard let household else { return false }
        return isAdmin || note.member_id == household.memberID
    }

    func loadRecipeNotes(for recipeID: String) async throws {
        guard !isDemo, let family = household else { return }
        let request = UUID()
        noteRequests[recipeID] = request
        let notes: [RecipeNote] = try await client.from("ep_recipe_notes")
            .select("id,member_id,body,created_at,updated_at").eq("recipe_id", value: recipeID)
            .order("created_at", ascending: false).execute().value
        guard !Task.isCancelled, household?.id == family.id, noteRequests[recipeID] == request else { return }
        recipeNotes[recipeID] = notes
    }

    func watchRecipeNotes(for recipeID: String) async {
        guard !isDemo, household != nil else { return }
        let channel = client.channel("ep-ios-notes-\(recipeID)-\(UUID())")
        let changed = channel.postgresChange(AnyAction.self, table: "ep_recipe_notes",
                                            filter: .eq("recipe_id", value: recipeID))
        let deleted = channel.postgresChange(DeleteAction.self, table: "ep_recipe_notes")
        do {
            try await channel.subscribeWithError()
            try? await loadRecipeNotes(for: recipeID)
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in changed { try? await self.loadRecipeNotes(for: recipeID) }
                }
                group.addTask {
                    for await event in deleted {
                        if let id = event.oldRecord["id"]?.stringValue,
                           await self.recipeNotes[recipeID]?.contains(where: { $0.id == id }) == true {
                            try? await self.loadRecipeNotes(for: recipeID)
                        }
                    }
                }
            }
        } catch {
            // The detail can retry its independent initial request.
        }
        await client.removeChannel(channel)
    }

    func saveRecipeNote(id: String, recipeID: String, body: String, editing existing: RecipeNote? = nil) async throws {
        guard let family = household, recipes.contains(where: { $0.id == recipeID }) else {
            throw HouseholdEditError.unavailable
        }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.unicodeScalars.count <= 4000 else { throw RecipeNoteError.invalidBody }
        if let existing, !canEditNote(existing) { throw HouseholdEditError.unavailable }
        let saved: RecipeNote
        if isDemo {
            let now = Date.now.ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            if let existing {
                saved = RecipeNote(id: existing.id, member_id: existing.member_id, body: text,
                                   created_at: existing.created_at, updated_at: now)
            } else {
                saved = recipeNotes[recipeID]?.first { $0.id == id }
                    ?? RecipeNote(id: id, member_id: family.memberID, body: text, created_at: now, updated_at: now)
            }
        } else if let existing {
            saved = try await client.from("ep_recipe_notes").update(["body": text]).eq("id", value: existing.id)
                .eq("recipe_id", value: recipeID).select("id,member_id,body,created_at,updated_at").single().execute().value
        } else {
            let row = ["id": id, "recipe_id": recipeID, "member_id": family.memberID, "body": text]
            try await client.from("ep_recipe_notes").upsert(row, onConflict: "id", ignoreDuplicates: true).execute()
            saved = try await client.from("ep_recipe_notes").select("id,member_id,body,created_at,updated_at")
                .eq("id", value: id).eq("recipe_id", value: recipeID).single().execute().value
        }
        guard household?.id == family.id else { return }
        noteRequests[recipeID] = nil
        if let index = recipeNotes[recipeID]?.firstIndex(where: { $0.id == saved.id }) {
            recipeNotes[recipeID]?[index] = saved
        } else {
            recipeNotes[recipeID, default: []].insert(saved, at: 0)
        }
    }

    func deleteRecipeNote(_ note: RecipeNote, recipeID: String) async throws {
        guard let family = household, canEditNote(note) else { throw HouseholdEditError.unavailable }
        if !isDemo {
            try await client.from("ep_recipe_notes").delete().eq("id", value: note.id)
                .eq("recipe_id", value: recipeID).execute()
        }
        guard household?.id == family.id else { return }
        noteRequests[recipeID] = nil
        recipeNotes[recipeID]?.removeAll { $0.id == note.id }
    }
}

extension HouseholdStore {
    func refreshCookingHistory(today: String = BerlinDay.today()) async {
        guard let family = household, !Task.isCancelled else { return }
        if isDemo {
            markDemoMealsCooked(before: today)
            return
        }
        do {
            let updated: Int = try await client.rpc("ep_mark_past_cooked").execute().value
            guard household?.id == family.id, !Task.isCancelled else { return }
            if updated > 0, let weekStart { await loadWeek(from: weekStart) }
        } catch {
            // An unavailable write should still allow the saved history to load.
        }
        guard household?.id == family.id, !Task.isCancelled else { return }
        await loadCookingHistory()
    }

    private func markDemoMealsCooked(before today: String) {
        // Mirror the plan trigger so the demo exercises the same rollover.
        for index in plan.indices {
            let entry = plan[index]
            guard entry.date < today, entry.status == .planned, entry.leftoverOf == nil, entry.recipeID != nil else { continue }
            let cooked = MealPlanEntry(id: entry.id, date: entry.date, meal: entry.meal, recipeID: entry.recipeID,
                                        cookID: entry.cookID, secondCookID: entry.secondCookID,
                                        servingsOverride: entry.servingsOverride, status: .cooked,
                                        note: entry.note, shoppedAt: entry.shoppedAt, familyGuests: entry.familyGuests)
            plan[index] = cooked
            updateDemoCookingHistory(for: cooked)
        }
    }

    private func updateDemoCookingHistory(for meal: MealPlanEntry) {
        let previous = cookingHistory.first { $0.meal_plan_id == meal.id }
        cookingHistory.removeAll { $0.meal_plan_id == meal.id }
        if meal.status == .cooked, meal.leftoverOf == nil, let recipe = meal.recipeID {
            cookingHistory.append(CookingRecord(id: previous?.id ?? UUID().uuidString, recipe_id: recipe,
                                               cooked_on: meal.date, meal_plan_id: meal.id, cook_id: meal.cookID,
                                               servings: meal.servingsOverride, source: .plan))
        }
    }

    func loadCookingHistory(reportFailure: Bool = true) async {
        guard !isDemo, let family = household, !Task.isCancelled else { return }
        let request = UUID()
        historyRequest = request
        do {
            var history: [CookingRecord] = []
            let pageSize = 500
            var offset = 0
            while !Task.isCancelled {
                let page: [CookingRecord] = try await client.from("ep_cooking_history")
                    .select().eq("household_id", value: family.id)
                    .order("cooked_on", ascending: false).order("id").range(from: offset, to: offset + pageSize - 1)
                    .execute().value
                history += page
                if page.count < pageSize { break }
                offset += page.count
            }
            if historyRequest == request, household?.id == family.id, !Task.isCancelled {
                for index in history.indices { history[index].loadLocalMeal() }
                cookingHistory = history
            }
        } catch {
            if reportFailure, historyRequest == request, household?.id == family.id, !Task.isCancelled {
                self.error = "Die Kochhistorie konnte nicht geladen werden."
            }
        }
    }

    func watchCookingHistory() async {
        guard !isDemo, let family = household else { return }
        await Backend.watchChanges(using: client, household: family.id, tables: ["ep_cooking_history"]) {
            guard self.household?.id == family.id else { return }
            await self.loadCookingHistory(reportFailure: false)
        }
    }

    func searchRecipeIDs(_ term: String) async throws -> Set<String> {
        guard !isDemo else { return [] }
        struct Hit: Decodable { let id: String }
        let hits: [Hit] = try await client.rpc("ep_search_recipes", params: ["q": term]).execute().value
        return Set(hits.map(\.id))
    }

    func saveFolder(id: String, name: String, emoji: String?, existing: Bool) async throws {
        guard let family = household else { throw HouseholdEditError.unavailable }
        let saved: RecipeFolder
        if isDemo {
            saved = RecipeFolder(id: id, name: name, emoji: emoji)
        } else {
            var fields: JSONObject = ["name": .string(name), "emoji": emoji.map(AnyJSON.string) ?? .null]
            if existing {
                saved = try await client.from("ep_recipe_folders").update(fields).eq("id", value: id)
                    .eq("household_id", value: family.id).select().single().execute().value
            } else {
                fields["id"] = .string(id)
                fields["household_id"] = .string(family.id)
                fields["position"] = .integer(folders.count)
                try await client.from("ep_recipe_folders").upsert(fields, onConflict: "id", ignoreDuplicates: true).execute()
                saved = try await client.from("ep_recipe_folders").select().eq("id", value: id)
                    .eq("household_id", value: family.id).single().execute().value
            }
        }
        guard household?.id == family.id else { return }
        if let index = folders.firstIndex(where: { $0.id == id }) { folders[index] = saved }
        else { folders.append(saved) }
    }

    func deleteFolder(_ folder: RecipeFolder) async throws {
        guard let family = household else { throw HouseholdEditError.unavailable }
        if !isDemo {
            try await client.from("ep_recipe_folders").delete().eq("id", value: folder.id)
                .eq("household_id", value: family.id).execute()
        }
        guard household?.id == family.id else { return }
        folders.removeAll { $0.id == folder.id }
        for index in recipes.indices where recipes[index].folderID == folder.id {
            recipes[index].folderID = nil
        }
    }

    func addCookingRecord(
        recipeID: String, day: String, servings: Int?, source: CookingRecord.Source, meal: Meal? = nil
    ) async throws {
        guard let family = household, source != .plan else { throw HouseholdEditError.unavailable }
        let direct = DirectCooking(householdID: family.id, recipeID: recipeID, day: day)
        if source == .manual {
            let alreadyCooked = cookingHistory.contains {
                $0.recipe_id == recipeID && $0.cooked_on == day && $0.source == .manual
            }
            guard !alreadyCooked, pendingDirectCooking.insert(direct).inserted else { return }
        }
        defer { if source == .manual { pendingDirectCooking.remove(direct) } }
        if isDemo {
            cookingHistory.insert(CookingRecord(id: UUID().uuidString, recipe_id: recipeID, cooked_on: day,
                                               meal_plan_id: nil, cook_id: family.memberID, servings: servings,
                                               source: source, meal: meal), at: 0)
            return
        }
        if source == .manual {
            let remote: [CookingRecord] = try await client.from("ep_cooking_history")
                .select().eq("household_id", value: family.id).eq("recipe_id", value: recipeID)
                .eq("cooked_on", value: day).eq("source", value: source.rawValue).limit(1).execute().value
            guard household?.id == family.id else { return }
            if !remote.isEmpty {
                await loadCookingHistory(reportFailure: false)
                return
            }
        }
        var row: JSONObject = [
            "household_id": .string(family.id), "recipe_id": .string(recipeID),
            "cooked_on": .string(day), "cook_id": .string(family.memberID),
            "servings": servings.map(AnyJSON.integer) ?? .null, "source": .string(source.rawValue)
        ]
        if let meal { row["meal"] = .string(meal.rawValue) }
        var saved: CookingRecord
        do {
            saved = try await client.from("ep_cooking_history").insert(row).select().single().execute().value
        } catch let error as PostgrestError where source == .manual && error.code == "23505"
            && error.message == "ep_direct_cooking_log_once" {
            guard household?.id == family.id else { return }
            await loadCookingHistory(reportFailure: false)
            return
        } catch let error as PostgrestError where meal != nil && error.code == "PGRST204" {
            // An older server can still store the history entry. Keep the meal on-device until it supports the field.
            row.removeValue(forKey: "meal")
            saved = try await client.from("ep_cooking_history").insert(row).select().single().execute().value
            saved.setLocalMeal(meal)
        }
        guard household?.id == family.id else { return }
        historyRequest = UUID()
        cookingHistory.removeAll { $0.id == saved.id }
        cookingHistory.insert(saved, at: 0)
        await loadCookingHistory(reportFailure: false)
    }

    func deleteCookingRecord(_ record: CookingRecord) async throws {
        guard let family = household, record.source != .plan else { throw HouseholdEditError.unavailable }
        if !isDemo {
            try await client.from("ep_cooking_history").delete().eq("id", value: record.id)
                .eq("household_id", value: family.id).eq("source", value: record.source.rawValue).execute()
        }
        guard household?.id == family.id else { return }
        historyRequest = UUID()
        cookingHistory.removeAll { $0.id == record.id }
        if record.meal != nil {
            var removed = record
            removed.setLocalMeal(nil)
        }
        await loadCookingHistory(reportFailure: false)
    }
}

extension HouseholdStore {
    func loadRatings(for recipeID: String) async throws -> [RecipeRating] {
        guard let family = household else { throw HouseholdEditError.unavailable }
        if isDemo { return demoRatings[recipeID] ?? [] }
        let ratings: [RecipeRating] = try await client.from("ep_recipe_ratings").select("member_id,stars")
            .eq("recipe_id", value: recipeID).order("member_id").execute().value
        guard household?.memberID == family.memberID else { throw HouseholdEditError.unavailable }
        return ratings
    }

    func saveRating(_ stars: Int, for recipeID: String) async throws -> RecipeRating {
        guard let family = household, (1...5).contains(stars) else { throw HouseholdEditError.unavailable }
        let rating = RecipeRating(memberID: family.memberID, stars: stars)
        if isDemo {
            demoRatings[recipeID, default: []].removeAll { $0.memberID == family.memberID }
            demoRatings[recipeID, default: []].append(rating)
            return rating
        }
        let fields: JSONObject = ["recipe_id": .string(recipeID), "member_id": .string(family.memberID),
                                  "stars": .integer(stars)]
        let saved: RecipeRating = try await client.from("ep_recipe_ratings")
            .upsert(fields, onConflict: "recipe_id,member_id").select("member_id,stars").single().execute().value
        guard household?.memberID == family.memberID else { throw HouseholdEditError.unavailable }
        return saved
    }

    private struct WeeklyBudget: Decodable, Sendable { let budget_cents: Int? }

    var weeklyBudgetCents: Int? { household.flatMap { weeklyBudgets[$0.id] } }

    func loadWeeklyBudget(for family: Membership) async throws -> Int? {
        guard household?.memberID == family.memberID else { throw HouseholdEditError.unavailable }
        if isDemo { return weeklyBudgets[family.id] }
        let revision = budgetRequest
        let rows: [WeeklyBudget] = try await client.from("ep_weekly_budgets").select("budget_cents")
            .eq("household_id", value: family.id).limit(1).execute().value
        guard household?.memberID == family.memberID else { throw HouseholdEditError.unavailable }
        if revision == budgetRequest { weeklyBudgets[family.id] = rows.first?.budget_cents }
        return weeklyBudgets[family.id]
    }

    func saveWeeklyBudget(_ cents: Int?, for family: Membership) async throws {
        guard household?.memberID == family.memberID,
              cents.map({ (1...FoodMoney.maxCents).contains($0) }) != false else {
            throw HouseholdEditError.unavailable
        }
        if !isDemo {
            let fields: JSONObject = ["household_id": .string(family.id), "budget_cents": cents.map(AnyJSON.integer) ?? .null]
            try await client.from("ep_weekly_budgets").upsert(fields, onConflict: "household_id").execute()
        }
        budgetRequest = UUID()
        weeklyBudgets[family.id] = cents
    }
}

extension HouseholdStore {
    func familyGuestCount(at slot: MealSlot) -> Int {
        Planning.guestCount(at: slot, members: members, attendance: attendance,
                            familyGuests: plan.first { $0.slot == slot }?.familyGuests)
    }

    func setFamilyGuestCount(_ count: Int, at slot: MealSlot) async {
        guard (0...10000).contains(count), !saving else { return }
        let entry = plan.first { $0.slot == slot }
        if !(await saveMeal(at: slot, changes: ["family_guests": .integer(count)],
                            condition: .unchanged(entry, includingDetails: true))), error == nil {
            error = "Die Anzahl der Gäste wurde inzwischen geändert."
        }
    }

    func toggleAttendance(for member: Member, at slot: MealSlot) async {
        guard !saving, let family = household else { return }
        let current = Planning.effectiveStatus(for: member, at: slot, attendance: attendance)
        if current.guests > 0, plan.first(where: { $0.slot == slot })?.familyGuests == nil {
            await setFamilyGuestCount(familyGuestCount(at: slot), at: slot)
            guard error == nil, household?.id == family.id else { return }
        }
        await setAttendance(for: member, at: slot, status: current.status == .present ? .away : .present, guests: 0)
    }

    func clearPlannedMeal(_ expected: MealPlanEntry) async throws {
        guard let family = household, !saving else { throw HouseholdEditError.unavailable }
        saving = true
        weekRequest = UUID()
        do {
            if isDemo {
                guard plan.first(where: { $0.slot == expected.slot })?.planningSnapshot == expected.planningSnapshot else {
                    throw AssistantFailure.planChanged
                }
                if isMealPrepSource(expected.id) {
                    throw AssistantFailure.message("Entferne zuerst die Reste, die mit diesem Gericht verknüpft sind.")
                }
            } else {
                let params: JSONObject = ["p_household": .string(family.id), "p_id": .string(expected.id),
                                          "p_expected": expected.planningSnapshot]
                try await client.rpc("ep_clear_planned_meal", params: params).execute()
            }
            if household?.id == family.id {
                plan.removeAll { $0.id == expected.id }
                attendance.removeAll { $0.date == expected.date && $0.meal == expected.meal }
            }
            saving = false
            if let weekStart, household?.id == family.id { await loadWeek(from: weekStart) }
        } catch {
            saving = false
            throw error
        }
    }

    func recentLeftoverSources(before target: MealSlot) async throws -> [MealPlanEntry] {
        let latest = target.date
        let earliest = BerlinDay.adding(-MealSlot.leftoverWindowDays, to: latest)
        let rows = try await plannedMeals(from: earliest, through: latest)
        let recipeIDs = Set(recipes.map(\.id))
        return rows.filter {
            $0.canBeLeftoverSource(for: target) && recipeIDs.contains($0.recipeID ?? "")
        }.sorted {
            if $0.date == $1.date { return $0.meal.displayOrder > $1.meal.displayOrder }
            return $0.date > $1.date
        }
    }

    func validateLeftoverSource(_ source: MealPlanEntry, for target: MealSlot) async throws {
        let familyID = household?.id
        let rows = try await plannedMeals(from: source.date, through: source.date)
        guard household?.id == familyID, let liveSource = rows.first(where: { $0.id == source.id }),
              liveSource.recipeID == source.recipeID, liveSource.canBeLeftoverSource(for: target) else {
            throw LeftoverScheduleError.sourceChanged
        }
    }

    func scheduleLeftover(from source: MealPlanEntry, at target: MealSlot, expected: MealPlanEntry?) async throws {
        try await validateLeftoverSource(source, for: target)
        if expected?.leftoverOf == source.id, expected?.status == .planned { return }
        let saved = await saveMeal(at: target, changes: [
            "recipe_id": .null, "leftover_of": .string(source.id), "status": .string(PlanStatus.planned.rawValue),
            "servings_override": .null, "shopped_at": .null
        ], condition: .unchanged(expected, includingDetails: true))
        if !saved {
            let message = error
            error = nil
            throw LeftoverScheduleError.saveFailed(message)
        }
    }

    private enum LeftoverScheduleError: LocalizedError {
        case sourceChanged
        case saveFailed(String?)

        var errorDescription: String? {
            switch self {
            case .sourceChanged: "Das Ursprungsgericht ist für diese Mahlzeit nicht mehr verfügbar."
            case .saveFailed(let message): message ?? "Die Mahlzeit wurde inzwischen geändert. Bitte wähle sie erneut."
            }
        }
    }
}


struct PlannedMealMove: Identifiable {
    let householdID: String
    let source: MealPlanEntry
    let target: MealSlot
    let destination: MealPlanEntry?
    var id: MealSlot { target }
    var needsConfirmation: Bool { destination?.recipeID != nil || destination?.leftoverOf != nil }
}

extension HouseholdStore {
    func prepareMealMove(from slot: MealSlot, to target: MealSlot, expectedID: String,
                         recipeID: String?, leftoverOf: String?) async throws -> PlannedMealMove {
        let today = BerlinDay.today()
        guard slot.date >= today, target.date >= today else {
            throw AssistantFailure.message("Gerichte lassen sich nur auf heutige oder zukünftige Termine ziehen.")
        }
        guard slot != target, let family = household, !saving else { throw AssistantFailure.planChanged }
        async let firstDay = plannedMeals(from: slot.date, through: slot.date)
        let secondDay = slot.date == target.date ? [] : try await plannedMeals(from: target.date, through: target.date)
        let rows = try await firstDay + secondDay
        guard let source = rows.first(where: { $0.slot == slot }), source.id == expectedID,
              source.recipeID == recipeID, source.leftoverOf == leftoverOf, source.status == .planned else {
            throw AssistantFailure.planChanged
        }
        let destination = rows.first { $0.slot == target }
        if destination?.status == .cancelled {
            throw AssistantFailure.message("Dieser Termin fällt aus. Wähle einen anderen Termin.")
        }
        let move = PlannedMealMove(householdID: family.id, source: source, target: target, destination: destination)
        try await validateMove(move)
        return move
    }

    func movePlannedMeal(_ move: PlannedMealMove) async throws {
        guard household?.id == move.householdID, !saving else { throw AssistantFailure.planChanged }
        if isDemo {
            guard plan.first(where: { $0.slot == move.source.slot })?.planningSnapshot == move.source.planningSnapshot,
                  plan.first(where: { $0.slot == move.target })?.planningSnapshot == move.destination?.planningSnapshot else {
                throw AssistantFailure.planChanged
            }
            try await validateMove(move)
            guard applyDemoPlanChange(.move(move.source.slot, move.target)) else { throw AssistantFailure.planChanged }
            return
        }
        let fields: JSONObject = [
            "p_household": .string(move.householdID), "p_from_date": .string(move.source.date),
            "p_from_meal": .string(move.source.meal.rawValue), "p_to_date": .string(move.target.date),
            "p_to_meal": .string(move.target.meal.rawValue), "p_expected_source": move.source.planningSnapshot,
            "p_expected_target": move.destination?.planningSnapshot ?? .null
        ]
        try await client.rpc("ep_plan_move_checked", params: fields).execute()
        if let weekStart, household?.id == move.householdID { await loadWeek(from: weekStart) }
    }

    private func validateMove(_ move: PlannedMealMove) async throws {
        let relevant: [MealPlanEntry]
        if isDemo {
            relevant = plan
        } else {
            let slots = [move.source, move.destination].compactMap { $0 }
            let origins = Set(slots.compactMap(\.leftoverOf)).subtracting(slots.map(\.id))
            async let children: [MealPlanEntry] = client.from("ep_meal_plan").select()
                .eq("household_id", value: move.householdID)
                .in("leftover_of", values: slots.map(\.id)).execute().value
            let parents: [MealPlanEntry] = if origins.isEmpty {
                []
            } else {
                try await client.from("ep_meal_plan").select().eq("household_id", value: move.householdID)
                    .in("id", values: Array(origins)).execute().value
            }
            var seen = Set<String>()
            relevant = try await (slots + children + parents).filter { seen.insert($0.id).inserted }
        }
        guard household?.id == move.householdID else { throw AssistantFailure.planChanged }
        guard PlanChange.move(move.source.slot, move.target).applying(to: relevant, purchases: [], today: BerlinDay.today()) != nil else {
            throw AssistantFailure.message("Das Ursprungsgericht muss vor den Resten und höchstens zehn Tage zurück liegen.")
        }
    }
}
