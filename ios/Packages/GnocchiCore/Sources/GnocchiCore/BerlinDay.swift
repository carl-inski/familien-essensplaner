import Foundation

public enum BerlinDay {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    public static func today(now: Date = .now) -> String {
        key(for: now)
    }

    public static func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public static func date(for key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static func adding(_ days: Int, to key: String) -> String {
        guard let date = date(for: key), let shifted = calendar.date(byAdding: .day, value: days, to: date) else {
            return key
        }
        return self.key(for: shifted)
    }

    public static func days(from start: String, count: Int = 7) -> [String] {
        (0..<max(0, count)).map { adding($0, to: start) }
    }

    public static func isoWeek(_ key: String) -> String? {
        guard let date = date(for: key) else { return nil }
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    static func weekday(_ key: String) -> String? {
        guard let date = date(for: key) else { return nil }
        let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        return weekdays[calendar.component(.weekday, from: date) - 1]
    }
}
