public enum Meal: String, Codable, Hashable, CaseIterable, Sendable {
    case breakfast = "fruehstueck"
    case lunch = "mittag"
    case dinner = "abend"
    case snack

    public static let planned: [Meal] = [.lunch, .dinner]

    public var displayOrder: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .dinner: 2
        case .snack: 3
        }
    }
}

public enum AttendanceStatus: String, Codable, Sendable {
    case present = "da"
    case away = "weg"
}

public enum PlanStatus: String, Codable, CaseIterable, Sendable {
    case planned = "geplant"
    case cooked = "gekocht"
    case cancelled = "ausgefallen"
}

public struct MealSlot: Codable, Hashable, Identifiable, Sendable {
    public static let leftoverWindowDays = 10
    public var id: Self { self }
    public let date: String
    public let meal: Meal

    public init(date: String, meal: Meal) {
        self.date = date
        self.meal = meal
    }

    public func precedes(_ other: Self) -> Bool {
        (date, meal.displayOrder) < (other.date, other.meal.displayOrder)
    }

    public func isWithinLeftoverWindow(before target: Self) -> Bool {
        precedes(target) && date >= BerlinDay.adding(-Self.leftoverWindowDays, to: target.date)
    }
}

public struct Member: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let avatarURL: String?
    public let defaultWeek: [String: [Meal: AttendanceStatus]]
    public let email: String?
    public let hasLogin: Bool
    public let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, email, role
        case userID = "user_id"
        case avatarURL = "avatar_url"
        case defaultWeek = "default_week"
    }

    public init(id: String, name: String, avatarURL: String? = nil, defaultWeek: [String: [Meal: AttendanceStatus]] = [:],
                email: String? = nil, hasLogin: Bool = false, isAdmin: Bool = false) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.defaultWeek = defaultWeek
        self.email = email
        self.hasLogin = hasLogin
        self.isAdmin = isAdmin
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let week = try values.decodeIfPresent([String: [String: AttendanceStatus]].self, forKey: .defaultWeek) ?? [:]
        self.init(
            id: try values.decode(String.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            avatarURL: try values.decodeIfPresent(String.self, forKey: .avatarURL),
            defaultWeek: week.mapValues { day in
                Dictionary(uniqueKeysWithValues: day.compactMap { key, value in
                    Meal(rawValue: key).map { ($0, value) }
                })
            },
            email: try values.decodeIfPresent(String.self, forKey: .email),
            hasLogin: try values.decodeIfPresent(String.self, forKey: .userID) != nil,
            isAdmin: try values.decodeIfPresent(String.self, forKey: .role) == "admin"
        )
    }
}

public enum StandardWeek {
    public static let days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    public static func updating(_ week: [String: [Meal: AttendanceStatus]], day: String, meal: Meal, present: Bool)
        -> [String: [Meal: AttendanceStatus]] {
        var updated = week
        var meals = week[day] ?? [:]
        meals[meal] = present ? nil : .away
        updated[day] = meals.isEmpty ? nil : meals
        return updated
    }
}

public struct Attendance: Decodable, Identifiable, Sendable {
    public let id: String
    public let memberID: String
    public let date: String
    public let meal: Meal
    public let status: AttendanceStatus
    public let guests: Int

    enum CodingKeys: String, CodingKey {
        case id, date, meal, status, guests
        case memberID = "member_id"
    }

    public init(id: String, memberID: String, date: String, meal: Meal, status: AttendanceStatus, guests: Int) {
        self.id = id
        self.memberID = memberID
        self.date = date
        self.meal = meal
        self.status = status
        self.guests = guests
    }
}

public struct MealPlanEntry: Decodable, Identifiable, Sendable {
    public let id: String
    public let date: String
    public let meal: Meal
    public let recipeID: String?
    public let leftoverOf: String?
    public let cookID: String?
    public let secondCookID: String?
    public let servingsOverride: Int?
    public let familyGuests: Int?
    public let status: PlanStatus
    public let note: String?
    public let shoppedAt: String?

    public var slot: MealSlot { MealSlot(date: date, meal: meal) }

    public func canBeLeftoverSource(for target: MealSlot) -> Bool {
        status != .cancelled && recipeID != nil && leftoverOf == nil && slot.isWithinLeftoverWindow(before: target)
    }

    public var isConfigured: Bool {
        status != .planned || recipeID != nil || leftoverOf != nil || !(note ?? "").isEmpty
            || cookID != nil || secondCookID != nil || servingsOverride != nil || shoppedAt != nil || (familyGuests ?? 0) > 0
    }

    enum CodingKeys: String, CodingKey {
        case id, date, meal, status, note
        case recipeID = "recipe_id"
        case leftoverOf = "leftover_of"
        case cookID = "cook_id"
        case secondCookID = "cook2_id"
        case servingsOverride = "servings_override"
        case familyGuests = "family_guests"
        case shoppedAt = "shopped_at"
    }

    public init(
        id: String, date: String, meal: Meal, recipeID: String? = nil, leftoverOf: String? = nil,
        cookID: String? = nil, secondCookID: String? = nil, servingsOverride: Int? = nil,
        status: PlanStatus = .planned, note: String? = nil, shoppedAt: String? = nil, familyGuests: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.meal = meal
        self.recipeID = recipeID
        self.leftoverOf = leftoverOf
        self.cookID = cookID
        self.secondCookID = secondCookID
        self.servingsOverride = servingsOverride
        self.familyGuests = familyGuests
        self.status = status
        self.note = note
        self.shoppedAt = shoppedAt
    }
}

public enum Planning {
    public static func configuredMeals(
        on date: String, plan: [MealPlanEntry], attendance: [Attendance]
    ) -> [Meal] {
        let entered = plan.lazy.filter { $0.date == date && $0.isConfigured }.map(\.meal)
        let attended = attendance.lazy.filter { $0.date == date }.map(\.meal)
        let configured = Set(entered).union(attended)
        return Meal.allCases.filter { configured.contains($0) }
    }

    public static func effectiveStatus(
        for member: Member, at slot: MealSlot, attendance: [Attendance]
    ) -> (status: AttendanceStatus, guests: Int, explicit: Bool) {
        if let row = attendance.first(where: {
            $0.memberID == member.id && $0.date == slot.date && $0.meal == slot.meal
        }) {
            return (row.status, row.status == .present ? row.guests : 0, true)
        }
        let weekday = BerlinDay.weekday(slot.date) ?? ""
        return (member.defaultWeek[weekday]?[slot.meal] ?? .present, 0, false)
    }

    public static func guestCount(at slot: MealSlot, members: [Member], attendance: [Attendance],
                                  familyGuests: Int? = nil) -> Int {
        if let familyGuests { return familyGuests }
        return members.reduce(0) { $0 + effectiveStatus(for: $1, at: slot, attendance: attendance).guests }
    }

    public static func eaters(at slot: MealSlot, members: [Member], attendance: [Attendance],
                              familyGuests: Int? = nil) -> Int {
        members.reduce(familyGuests ?? 0) { count, member in
            let state = effectiveStatus(for: member, at: slot, attendance: attendance)
            guard state.status == .present else { return count }
            return count + 1 + (familyGuests == nil ? state.guests : 0)
        }
    }

    public static func servings(
        for entry: MealPlanEntry, in plan: [MealPlanEntry], members: [Member], attendance: [Attendance]
    ) -> Int {
        if let override = entry.servingsOverride, override != 0 { return override }
        let leftovers = plan.filter { $0.leftoverOf == entry.id && $0.status != .cancelled }
        return ([entry] + leftovers).reduce(0) {
            $0 + eaters(at: $1.slot, members: members, attendance: attendance, familyGuests: $1.familyGuests)
        }
    }
}
