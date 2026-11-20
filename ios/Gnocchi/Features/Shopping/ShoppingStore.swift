import Foundation
import GnocchiCore
import Observation
import Supabase

struct ShoppingExtra: Decodable, Identifiable, Sendable {
    let id: String
    let text: String
    var key: String { "x:" + id }
}

private struct PantryEntry: Decodable, Sendable {
    let name: String
}

struct ShoppingPlanRow: Decodable, Sendable {
    static let selection = "*,recipe:ep_recipes(title,image_url,servings,ep_recipe_ingredients(id,name,position,amount,unit,aisle))"
    let entry: MealPlanEntry
    let recipe: ShoppingRecipe?
    let imageURL: URL?

    private enum CodingKeys: String, CodingKey { case recipe }

    private struct RecipePayload: Decodable {
        let title: String
        let image_url: String?
        let servings: Int?
        let ep_recipe_ingredients: [Recipe.Ingredient]
    }

    init(from decoder: any Decoder) throws {
        entry = try MealPlanEntry(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payload = try container.decodeIfPresent(RecipePayload.self, forKey: .recipe)
        recipe = payload.map {
            ShoppingRecipe(title: $0.title, servings: $0.servings, ingredients: $0.ep_recipe_ingredients.map(\.shoppingIngredient))
        }
        imageURL = payload.flatMap { recipe in
            let path = recipe.image_url.flatMap { $0.isEmpty ? nil : $0 }
                ?? RecipePhotoCredit.credit(title: recipe.title, imagePath: nil)?.src
            return path.flatMap { URL(string: $0, relativeTo: Backend.site)?.absoluteURL }
        }
    }
}

private struct PurchaseRow: Decodable, Sendable {
    let purchase: Purchase

    private enum CodingKeys: String, CodingKey {
        case name, amount, unit, source
        case clientID = "client_id"
        case dishID = "meal_plan_id"
        case key = "item_key"
        case boughtAt = "bought_at"
        case boughtBy = "bought_by"
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let amount = (try? values.decode(Double.self, forKey: .amount))
            ?? (try? values.decode(String.self, forKey: .amount)).flatMap(Double.init)
        purchase = Purchase(id: try values.decode(String.self, forKey: .clientID),
                            dishID: try values.decodeIfPresent(String.self, forKey: .dishID),
                            key: try values.decode(String.self, forKey: .key),
                            name: try values.decode(String.self, forKey: .name),
                            amount: amount, unit: try values.decodeIfPresent(String.self, forKey: .unit),
                            boughtAt: try values.decode(Date.self, forKey: .boughtAt),
                            isStock: try values.decodeIfPresent(String.self, forKey: .source) == "vorrat",
                            boughtBy: try values.decodeIfPresent(String.self, forKey: .boughtBy))
    }
}

@MainActor
@Observable
final class ShoppingStore {
    enum PurchaseChange: Codable, Equatable, Sendable {
        case buy([NewPurchase], at: Date)
        case undo(Set<String>)

        func apply(to purchases: inout [Purchase]) {
            switch self {
            case let .buy(rows, date):
                let existing = Set(purchases.map(\.id))
                purchases += rows.filter { !existing.contains($0.client_id) }.map { $0.purchase(at: date) }
            case let .undo(ids):
                purchases.removeAll { ids.contains($0.id) }
            }
        }
    }

    typealias WritePurchaseChange = @MainActor (PurchaseChange, String) async throws -> Void

    enum PurchaseSyncState { case current, sending, waiting }

    private let client = Backend.client
    private(set) var plan: [MealPlanEntry] = []
    private(set) var recipes: [String: ShoppingRecipe] = [:]
    private(set) var recipeImages: [String: URL] = [:]
    private(set) var attendance: [Attendance] = []
    private(set) var pantry: Set<String> = []
    private var confirmedPurchases: [Purchase] = []
    private var purchaseWindowStart: String?
    var purchases: [Purchase] {
        purchaseQueue.reduce(into: confirmedPurchases) { $1.apply(to: &$0) }
    }
    private(set) var extras: [ShoppingExtra] = []
    private(set) var loaded = false
    private(set) var saving = false
    private(set) var canUndoCompletion = false
    var error: String?
    private var revision = UUID()
    private var purchaseQueue: [PurchaseChange] = []
    private(set) var purchaseSyncState: PurchaseSyncState = .current
    var hasPendingPurchases: Bool { !purchaseQueue.isEmpty }
    @ObservationIgnored private let writePurchaseChange: WritePurchaseChange
    @ObservationIgnored private let completeShopping: (@MainActor (CompletionRequest) async throws -> Receipt)?
    @ObservationIgnored private var queueFile: URL?
    private var pendingCompletion: CompletionRequest?
    var hasPendingCompletion: Bool { pendingCompletion != nil }
    private var completedTrip: (id: String, receipt: Receipt)?

    init(completeShopping: (@MainActor (CompletionRequest) async throws -> Receipt)? = nil,
         writePurchaseChange: @escaping WritePurchaseChange = ShoppingStore.persistPurchaseChange) {
        self.writePurchaseChange = writePurchaseChange
        self.completeShopping = completeShopping
    }

    static func queueFile(for family: Membership, in directory: URL) -> URL? {
        guard let household = UUID(uuidString: family.id), let member = UUID(uuidString: family.memberID) else { return nil }
        return directory.appending(path: "\(household.uuidString)-\(member.uuidString).json")
    }

    func restoreLocalChanges(for family: Membership) {
        guard queueFile == nil, let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let file = Self.queueFile(for: family, in: support.appending(path: "ShoppingQueue")) else { return }
        restoreLocalChanges(from: file)
    }

    func restoreLocalChanges(from file: URL) {
        guard queueFile == nil, purchaseQueue.isEmpty, !hasPendingCompletion else { return }
        queueFile = file
        do {
            purchaseQueue = try Self.readPurchaseQueue(from: file)
            if !purchaseQueue.isEmpty { purchaseSyncState = .waiting }
        } catch {
            self.error = "Ausstehende Einkaufshaken konnten nicht geladen werden."
        }
        do {
            if let completionFile {
                pendingCompletion = try Self.readLocal(CompletionRequest?.self, from: completionFile) ?? nil
            }
        } catch {
            self.error = "Ein ausstehender Einkaufsabschluss konnte nicht geladen werden."
        }
    }

    private var completionFile: URL? {
        queueFile?.deletingPathExtension().appendingPathExtension("completion").appendingPathExtension("json")
    }

    private static func readPurchaseQueue(from file: URL) throws -> [PurchaseChange] {
        try readLocal([PurchaseChange].self, from: file) ?? []
    }

    private static func readLocal<Value: Decodable>(_ type: Value.Type, from file: URL) throws -> Value? {
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: file))
        } catch let failure as CocoaError where failure.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private static func writeLocal<Value: Encodable>(_ value: Value, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
    }

    private func replacePurchaseQueue(with next: [PurchaseChange]) -> Bool {
        do {
            if let queueFile {
                guard try Self.readPurchaseQueue(from: queueFile) == purchaseQueue else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try Self.writeLocal(next, to: queueFile)
            }
            purchaseQueue = next
            return true
        } catch {
            self.error = "Der Stand der Einkaufshaken konnte auf diesem iPhone nicht gespeichert werden."
            return false
        }
    }

    private func replacePendingCompletion(with next: CompletionRequest?) -> Bool {
        do {
            if let completionFile {
                let stored = try Self.readLocal(CompletionRequest?.self, from: completionFile) ?? nil
                guard stored == pendingCompletion else { throw CocoaError(.fileWriteUnknown) }
                try Self.writeLocal(next, to: completionFile)
            }
            pendingCompletion = next
            return true
        } catch {
            self.error = "Der Einkaufsabschluss konnte auf diesem iPhone nicht gespeichert werden."
            return false
        }
    }

    func changePantry(_ names: Set<String>, adding: Bool, family: Membership, demo: Bool) async -> Bool {
        guard !names.isEmpty, !saving else { return false }
        guard !adding || names.allSatisfy({ Pantry.isValid($0) && $0.unicodeScalars.count <= 80 }) else {
            error = "Ein Vorratseintrag darf höchstens 80 Zeichen lang sein."
            return false
        }
        saving = true
        revision = UUID()
        defer { saving = false }
        do {
            if !demo {
                if adding {
                    try await client.from("ep_pantry").upsert(
                        names.sorted().map { ["household_id": family.id, "name": $0] },
                        onConflict: "household_id,name", returning: .minimal, ignoreDuplicates: true
                    ).execute()
                } else {
                    try await client.from("ep_pantry").delete().eq("household_id", value: family.id)
                        .in("name", values: names.sorted()).execute()
                }
            }
            if adding { pantry.formUnion(names) }
            else { pantry.subtract(names) }
            return true
        } catch {
            self.error = "Der Vorrat konnte nicht geändert werden."
            return false
        }
    }

    struct RemovedExtra: Decodable, Sendable {
        let id: String
        let text: String
        let member_id: String?
        let aisle: String?
        let carried: Bool
        let created_at: String
    }

    struct Receipt: Decodable, Sendable {
        let timestamp: String
        let meal_ids: [String]
        let purchase_ids: [String]
        let extras: [RemovedExtra]
    }

    struct CompletionRequest: Codable, Equatable, Sendable {
        let p_household: String
        private(set) var p_completion_id = UUID().uuidString.lowercased()
        let p_purchases: [NewPurchase]
        let p_meals: [String]
        let p_extras: [String]
        var p_expected_dishes: CompletionExpectation? = nil
    }

    struct CompletionExpectation: Codable, Equatable, Sendable {
        struct Dish: Codable, Equatable, Sendable {
            let id: String
            let recipe_id: String?
            let servings_override: Int?
            let shopped_at: String?
            let purchase_ids: [String]
        }

        let bought_since: String
        let dishes: [Dish]
    }

    func load(family: Membership, members: [Member], today: String, reportFailure: Bool = true) async {
        guard !saving, !Task.isCancelled else { return }
        let current = UUID()
        revision = current
        let end = BerlinDay.adding(Shopping.horizonDays, to: today)
        let cutoff = BerlinDay.adding(-Shopping.stockDays - 1, to: today) + "T00:00:00Z"
        do {
            async let dishes: [ShoppingPlanRow] = client.from("ep_meal_plan").select(ShoppingPlanRow.selection)
                .eq("household_id", value: family.id).gte("date", value: today).lte("date", value: end)
                .order("date").order("meal", ascending: false).execute().value
            async let bought = loadPurchases(householdID: family.id, boughtSince: cutoff)
            async let supply: [PantryEntry] = client.from("ep_pantry").select("name")
                .eq("household_id", value: family.id).execute().value
            async let additional: [ShoppingExtra] = client.from("ep_shopping_extra").select("id,text")
                .eq("household_id", value: family.id).order("created_at").execute().value
            let (nextPlan, boughtRows, pantryRows, nextExtras) = try await (dishes, bought, supply, additional)
            let lateSourceIDs = nextPlan.map(\.entry).filter {
                Shopping.isShoppable($0, today: today) && $0.date > BerlinDay.adding(-MealSlot.leftoverWindowDays, to: end)
            }.map(\.id)
            let lateLeftovers: [MealPlanEntry] = if lateSourceIDs.isEmpty {
                []
            } else {
                try await client.from("ep_meal_plan").select().eq("household_id", value: family.id)
                    .in("leftover_of", values: lateSourceIDs).gt("date", value: end).execute().value
            }
            let attendanceEnd = lateLeftovers.map(\.date).max() ?? end
            let present: [Attendance] = if members.isEmpty {
                []
            } else {
                try await client.from("ep_attendance").select().in("member_id", values: members.map(\.id))
                    .gte("date", value: today).lte("date", value: attendanceEnd).execute().value
            }
            guard revision == current, !Task.isCancelled else { return }
            plan = nextPlan.map(\.entry) + lateLeftovers
            recipes = nextPlan.reduce(into: [:]) { recipes, row in
                if let id = row.entry.recipeID, let recipe = row.recipe { recipes[id] = recipe }
            }
            recipeImages = nextPlan.reduce(into: [:]) { images, row in
                if let id = row.entry.recipeID, let url = row.imageURL { images[id] = url }
            }
            attendance = present
            pantry = Set(pantryRows.map(\.name))
            confirmedPurchases = boughtRows.map(\.purchase)
            purchaseWindowStart = cutoff
            extras = nextExtras
            loaded = true
        } catch {
            guard revision == current, !Task.isCancelled else { return }
            if reportFailure, !loaded || !Self.canRetry(error) { self.error = "Die Einkaufsliste konnte nicht geladen werden." }
        }
    }

    private func loadPurchases(householdID: String, boughtSince: String) async throws -> [PurchaseRow] {
        let pageSize = 500
        var rows: [PurchaseRow] = []
        while true {
            try Task.checkCancellation()
            let page: [PurchaseRow] = try await client.from("ep_purchases").select()
                .eq("household_id", value: householdID).gte("bought_at", value: boughtSince)
                .order("bought_at").order("client_id").range(from: rows.count, to: rows.count + pageSize - 1)
                .execute().value
            rows.append(contentsOf: page)
            if page.count < pageSize { return rows }
        }
    }

    func watch(family: Membership, members: [Member], today: String) async {
        await load(family: family, members: members, today: today)
        await Backend.watchChanges(using: client, household: family.id,
                                   tables: ["ep_meal_plan", "ep_attendance", "ep_pantry", "ep_purchases", "ep_shopping_extra"]) {
            await self.load(family: family, members: members, today: today, reportFailure: false)
        }
    }

    @discardableResult
    func buy(_ line: ShoppingLine, family: Membership, fromStock: Bool, demo: Bool) -> Bool {
        let rows = line.parts.map {
            NewPurchase(household_id: family.id, meal_plan_id: $0.dishID, item_key: $0.key, name: $0.name,
                        amount: $0.amount, unit: $0.unit, bought_by: family.memberID,
                        source: fromStock ? "vorrat" : "kauf")
        }
        guard !rows.isEmpty else { return false }
        return enqueuePurchase(.buy(rows, at: .now), family: family, demo: demo)
    }

    func loadRecipe(_ id: String, householdID: String) async throws -> Recipe {
        try await client.from("ep_recipes")
            .select("*,ep_recipe_ingredients(id,name,amount,unit,amount_text,group_name,position,aisle)")
            .eq("household_id", value: householdID).eq("id", value: id).single().execute().value
    }

    func addStock(_ text: String, family: Membership, demo: Bool) async -> Bool {
        let entries = text.components(separatedBy: CharacterSet(charactersIn: ",").union(.newlines))
            .compactMap(Shopping.stockEntry)
        guard !entries.isEmpty else { return false }
        guard entries.allSatisfy({ $0.name.unicodeScalars.count <= 200 && $0.key.unicodeScalars.count <= 200 }) else {
            error = "Der Name einer Zutat ist zu lang."
            return false
        }
        let rows = entries.map {
            NewPurchase(household_id: family.id, meal_plan_id: nil, item_key: $0.key, name: $0.name,
                        amount: $0.quantity?.amount, unit: $0.quantity?.unit, bought_by: family.memberID, source: "vorrat")
        }
        return enqueuePurchase(.buy(rows, at: .now), family: family, demo: demo)
    }

    func completionExpectation(for mealIDs: Set<String>) -> CompletionExpectation? {
        guard let purchaseWindowStart else { return nil }
        let purchases = Dictionary(grouping: confirmedPurchases, by: \.dishID)
        let dishes = plan.filter { mealIDs.contains($0.id) }.sorted { $0.id < $1.id }.map { meal in
            CompletionExpectation.Dish(id: meal.id, recipe_id: meal.recipeID, servings_override: meal.servingsOverride,
                                       shopped_at: meal.shoppedAt, purchase_ids: (purchases[meal.id] ?? []).map(\.id).sorted())
        }
        return CompletionExpectation(bought_since: purchaseWindowStart, dishes: dishes)
    }

    func finish(lines: [ShoppingLine], mealIDs: Set<String>, extraIDs: Set<String>, household: HouseholdStore,
                expected: CompletionExpectation? = nil) async -> Bool {
        guard !saving, let family = household.household else { return false }
        guard household.isDemo || expected != nil else {
            error = "Die Einkaufsliste wird geladen. Schließe den Einkauf danach erneut ab."
            return false
        }
        if !household.isDemo { restoreLocalChanges(for: family) }
        guard !hasPendingPurchases, !hasPendingCompletion else { return false }
        let rows = lines.flatMap(\.parts).map {
            NewPurchase(household_id: family.id, meal_plan_id: $0.dishID, item_key: $0.key, name: $0.name,
                        amount: $0.amount, unit: $0.unit, bought_by: family.memberID, source: "kauf")
        }
        guard replacePendingCompletion(with: CompletionRequest(p_household: family.id, p_purchases: rows,
                                       p_meals: mealIDs.sorted(), p_extras: extraIDs.sorted(),
                                       p_expected_dishes: expected)) else { return false }
        return await retryCompletion(household: household)
    }

    func retryCompletion(household: HouseholdStore) async -> Bool {
        guard !saving, !hasPendingPurchases, let family = household.household, let request = pendingCompletion,
              request.p_household == family.id else { return false }
        saving = true
        revision = UUID()
        defer { saving = false }
        do {
            let receipt: Receipt
            if let completeShopping {
                receipt = try await completeShopping(request)
            } else if household.isDemo {
                let timestamp = Date.now
                let mark = timestamp.ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
                let markedIDs = household.plan.filter { request.p_meals.contains($0.id) && $0.shoppedAt == nil }.map(\.id)
                let removed = extras.filter { request.p_extras.contains($0.id) }.map {
                    RemovedExtra(id: $0.id, text: $0.text, member_id: family.memberID, aisle: nil,
                                 carried: false, created_at: mark)
                }
                confirmedPurchases += request.p_purchases.map { $0.purchase(at: timestamp) }
                household.setDemoShoppingMarker(mealIDs: Set(markedIDs), timestamp: mark)
                receipt = Receipt(timestamp: mark, meal_ids: markedIDs, purchase_ids: request.p_purchases.map(\.client_id), extras: removed)
            } else {
                receipt = try await Self.persistCompletion(request)
            }
            guard replacePendingCompletion(with: nil) else { return false }
            let removedKeys = Set(receipt.extras.map { "x:" + $0.id })
            confirmedPurchases.removeAll { removedKeys.contains($0.key) }
            extras.removeAll { removedKeys.contains($0.key) }
            completedTrip = (request.p_completion_id, receipt)
            canUndoCompletion = true
            return true
        } catch let failure as PostgrestError where failure.code == "40001" {
            if replacePendingCompletion(with: nil) {
                error = "Die Einkaufsliste hat sich geändert. Prüfe den aktuellen Stand und schließe den Einkauf erneut ab."
            }
            return false
        } catch {
            if !Task.isCancelled, !Self.canRetry(error), !(error is DecodingError) {
                if replacePendingCompletion(with: nil) { self.error = "Der Einkauf konnte nicht abgeschlossen werden." }
            }
            return false
        }
    }

    private static func persistCompletion(_ request: CompletionRequest) async throws -> Receipt {
        try await Backend.client.rpc("ep_complete_shopping", params: request).execute().value
    }

    func undoCompletion(household: HouseholdStore) async -> Bool {
        guard !saving, !hasPendingPurchases, !hasPendingCompletion, let family = household.household,
              let trip = completedTrip else { return false }
        let receipt = trip.receipt
        saving = true
        revision = UUID()
        defer { saving = false }
        do {
            if household.isDemo {
                let markedIDs = household.plan.filter {
                    receipt.meal_ids.contains($0.id) && $0.shoppedAt == receipt.timestamp
                }.map(\.id)
                household.setDemoShoppingMarker(mealIDs: Set(markedIDs), timestamp: nil)
                confirmedPurchases.removeAll { receipt.purchase_ids.contains($0.id) }
                let existing = Set(extras.map(\.id))
                extras += receipt.extras.filter { !existing.contains($0.id) }.map { ShoppingExtra(id: $0.id, text: $0.text) }
            } else {
                try await client.rpc("ep_undo_shopping_completion", params: [
                    "p_household": family.id, "p_completion_id": trip.id
                ]).execute()
            }
            completedTrip = nil
            canUndoCompletion = false
            return true
        } catch {
            self.error = "Der Einkaufsabschluss konnte nicht rückgängig gemacht werden."
            return false
        }
    }

    func returnMeal(_ entry: MealPlanEntry, household: HouseholdStore) async -> Bool {
        guard !saving, !hasPendingPurchases, let family = household.household else { return false }
        saving = true
        revision = UUID()
        defer { saving = false }
        do {
            if household.isDemo {
                household.setDemoShoppingMarker(mealIDs: [entry.id], timestamp: nil)
            } else {
                try await client.rpc("ep_return_meal_to_shopping", params: [
                    "p_household": family.id, "p_meal": entry.id
                ]).execute()
            }
            confirmedPurchases.removeAll { $0.dishID == entry.id }
            return true
        } catch {
            self.error = "Das Gericht konnte nicht zurück auf die Liste gesetzt werden."
            return false
        }
    }

    func toggleExtra(_ extra: ShoppingExtra, family: Membership, demo: Bool) async {
        let ids = purchases.filter { $0.key == extra.key }.map(\.id)
        if !ids.isEmpty {
            await undo(ids, family: family, demo: demo)
            return
        }
        let row = NewPurchase(household_id: family.id, meal_plan_id: nil, item_key: extra.key, name: extra.text,
                              amount: nil, unit: nil, bought_by: family.memberID, source: "kauf")
        _ = enqueuePurchase(.buy([row], at: .now), family: family, demo: demo)
    }

    private func enqueuePurchase(_ change: PurchaseChange, family: Membership, demo: Bool) -> Bool {
        guard !saving else { return false }
        revision = UUID()
        if demo {
            change.apply(to: &confirmedPurchases)
            return true
        }
        restoreLocalChanges(for: family)
        guard replacePurchaseQueue(with: purchaseQueue + [change]) else { return false }
        if purchaseSyncState == .current { purchaseSyncState = .waiting }
        return true
    }

    func undo(_ ids: [String], family: Membership, demo: Bool) async {
        guard !ids.isEmpty else { return }
        _ = enqueuePurchase(.undo(Set(ids)), family: family, demo: demo)
    }

    func syncPurchases(family: Membership) async {
        guard !saving, purchaseSyncState != .sending, !purchaseQueue.isEmpty else { return }
        purchaseSyncState = .sending
        defer { purchaseSyncState = purchaseQueue.isEmpty ? .current : .waiting }
        while let change = purchaseQueue.first, !Task.isCancelled {
            do {
                try await writePurchaseChange(change, family.id)
                revision = UUID()
                change.apply(to: &confirmedPurchases)
            } catch {
                if Task.isCancelled || Self.canRetry(error) { return }
                self.error = "Eine Änderung an der Einkaufsliste wurde abgelehnt. Die Liste bleibt auf dem gespeicherten Stand."
            }
            guard replacePurchaseQueue(with: Array(purchaseQueue.dropFirst())) else { return }
        }
    }

    private static func persistPurchaseChange(_ change: PurchaseChange, householdID: String) async throws {
        switch change {
        case let .buy(rows, _):
            try await Backend.client.from("ep_purchases").upsert(rows, onConflict: "client_id",
                returning: .minimal, ignoreDuplicates: true).execute()
        case let .undo(ids):
            try await Backend.client.from("ep_purchases").delete().eq("household_id", value: householdID)
                .in("client_id", values: ids.sorted()).execute()
        }
    }

    private static func canRetry(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let failure = error as? HTTPError {
            let status = failure.response.statusCode
            return status == 408 || status == 429 || (500..<600).contains(status)
        }
        if let failure = error as? PostgrestError {
            guard let code = failure.code, !code.isEmpty else { return true }
            return ["PGRST000", "PGRST001", "PGRST002", "PGRST003"].contains(code)
        }
        return false
    }

    @discardableResult
    func addExtra(_ text: String, family: Membership, demo: Bool) async -> Bool {
        guard !saving else { return false }
        saving = true
        revision = UUID()
        defer { saving = false }
        do {
            let extra: ShoppingExtra
            if demo {
                extra = ShoppingExtra(id: UUID().uuidString, text: text)
            } else {
                extra = try await client.from("ep_shopping_extra")
                    .insert(["household_id": family.id, "member_id": family.memberID, "text": text])
                    .select("id,text").single().execute().value
            }
            extras.append(extra)
            return true
        } catch {
            self.error = "Der Eintrag konnte nicht hinzugefügt werden."
            return false
        }
    }

    func deleteExtra(_ extra: ShoppingExtra, family: Membership, demo: Bool) async {
        guard !saving, !hasPendingPurchases else { return }
        saving = true
        revision = UUID()
        defer { saving = false }
        do {
            if !demo {
                try await client.from("ep_shopping_extra").delete().eq("household_id", value: family.id)
                    .eq("id", value: extra.id).execute()
            }
            extras.removeAll { $0.id == extra.id }
        } catch {
            self.error = "Der Eintrag konnte nicht entfernt werden."
        }
    }

    func bringURL(for lines: [ShoppingLine], extras: [ShoppingExtra], family: Membership, today: String) async -> URL? {
        guard !saving, let week = BerlinDay.isoWeek(today) else { return nil }
        saving = true
        defer { saving = false }
        struct Item: Encodable {
            let name: String
            let text: String
            let aisle: String
            let recipes: [String]
        }
        struct Export: Encodable {
            let household_id: String
            let iso_week: String
            let items: [Item]
            let exported_at: Date
        }
        struct Response: Decodable {
            let public_slug: String
        }
        let items = extras.map { Item(name: $0.text, text: $0.text, aisle: Aisles.forIngredient($0.text), recipes: []) }
            + lines.map { Item(name: $0.name, text: $0.text, aisle: $0.aisle, recipes: $0.recipeTitles) }
        do {
            let response: Response = try await client.from("ep_shopping_lists")
                .upsert(Export(household_id: family.id, iso_week: week, items: items, exported_at: .now),
                        onConflict: "household_id,iso_week")
                .select("public_slug").single().execute().value
            let publicURL = Backend.site.appending(path: "einkauf").appending(path: response.public_slug)
                .appending(queryItems: [URLQueryItem(name: "v", value: Shopping.exportVersion(items.map(\.text)))])
            return Backend.bringURL(for: publicURL)
        } catch {
            self.error = "Die Liste konnte nicht an Bring! übergeben werden."
            return nil
        }
    }
}

struct NewPurchase: Codable, Equatable, Sendable {
    private(set) var client_id = UUID().uuidString.lowercased()
    let household_id: String
    let meal_plan_id: String?
    let item_key: String
    let name: String
    let amount: Double?
    let unit: String?
    let bought_by: String
    let source: String

    func purchase(at date: Date) -> Purchase {
        Purchase(id: client_id, dishID: meal_plan_id, key: item_key, name: name,
                 amount: amount, unit: unit, boughtAt: date, isStock: source == "vorrat", boughtBy: bought_by)
    }
}
