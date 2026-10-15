import Foundation
import WidgetKit

enum ScheduleWidgetKind {
    static let calendar = "ScheduleCalendarWidget"
}

struct ScheduleWidgetTask: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var year: Int
    var month: Int
    var day: Int
    var isAllDay: Bool
    var minutesFromMidnight: Int?
}

struct ScheduleWidgetSnapshot: Codable {
    var householdId: UUID?
    var generatedAt: Date
    var localeIdentifier: String
    var timeZoneIdentifier: String
    var tasks: [ScheduleWidgetTask]

    var locale: Locale { Locale(identifier: localeIdentifier) }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        calendar.locale = locale
        return calendar
    }

    func tasks(on date: Date) -> [ScheduleWidgetTask] {
        let calendar = calendar
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return tasks
            .filter { $0.year == year && $0.month == month && $0.day == day }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return (lhs.minutesFromMidnight ?? 0) < (rhs.minutesFromMidnight ?? 0)
            }
    }

    func hasTask(year: Int, month: Int, day: Int) -> Bool {
        tasks.contains { $0.year == year && $0.month == month && $0.day == day }
    }
}

enum ScheduleWidgetLink {
    enum Route: Equatable {
        case openDay(year: Int, month: Int, day: Int)
        case createTask(year: Int, month: Int, day: Int)
    }

    static func openDay(year: Int, month: Int, day: Int) -> URL {
        url(year: year, month: month, day: day, create: false)
    }

    static func createTask(year: Int, month: Int, day: Int) -> URL {
        url(year: year, month: month, day: day, create: true)
    }

    static func components(of date: Date, calendar: Calendar) -> (year: Int, month: Int, day: Int) {
        (
            calendar.component(.year, from: date),
            calendar.component(.month, from: date),
            calendar.component(.day, from: date)
        )
    }

    static func parse(_ url: URL) -> Route? {
        guard url.scheme == "aifamily", url.host == "schedule" else { return nil }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "date" })?.value else {
            return nil
        }
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            return nil
        }
        let create = items.contains { $0.name == "create" && $0.value == "1" }
        if create {
            return .createTask(year: year, month: month, day: day)
        }
        return .openDay(year: year, month: month, day: day)
    }

    private static func url(year: Int, month: Int, day: Int, create: Bool) -> URL {
        var components = URLComponents()
        components.scheme = "aifamily"
        components.host = "schedule"
        var items = [
            URLQueryItem(name: "date", value: String(format: "%04d-%02d-%02d", year, month, day))
        ]
        if create {
            items.append(URLQueryItem(name: "create", value: "1"))
        }
        components.queryItems = items
        return components.url ?? URL(string: "aifamily://schedule")!
    }
}

enum ScheduleWidgetSnapshotStore {
    static let appGroupID = "group.com.aifamilygroup.reminder"
    private static let snapshotKey = "schedule.widget.snapshot"

    static func save(_ snapshot: ScheduleWidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: ScheduleWidgetKind.calendar)
    }

    static func load() -> ScheduleWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(ScheduleWidgetSnapshot.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: ScheduleWidgetKind.calendar)
    }
}
