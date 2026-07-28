import Foundation

/// 本机日程「显示时区」偏好（`@AppStorage` / UserDefaults），默认跟随系统。
enum AppDisplayTimeZone {
    static let storageKey = "app_display_timezone"

    /// MVP curated IANA 列表（设置页）；完整搜索后续增强。
    static let curatedIdentifiers: [String] = [
        "Asia/Shanghai",
        "Asia/Hong_Kong",
        "Asia/Tokyo",
        "Asia/Singapore",
        "Asia/Dubai",
        "Europe/London",
        "Europe/Paris",
        "America/New_York",
        "America/Los_Angeles",
        "America/Chicago",
        "Australia/Sydney",
        "UTC"
    ]

    /// `nil` = 跟随系统。
    static var preferredIdentifier: String? {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var effectiveTimeZone: TimeZone {
        if let id = preferredIdentifier, let zone = TimeZone(identifier: id) {
            return zone
        }
        return .current
    }

    static func calendar(for timeZone: TimeZone = effectiveTimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// 设置列表展示名（城市段 + 当前 UTC 偏移）。
    static func displayName(forIdentifier identifier: String, locale: Locale = .current) -> String {
        let city = identifier.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "_", with: " ")
            ?? identifier
        guard let zone = TimeZone(identifier: identifier) else { return city }
        let seconds = zone.secondsFromGMT()
        let sign = seconds >= 0 ? "+" : "-"
        let absSeconds = abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        let offset: String
        if minutes == 0 {
            offset = String(format: "GMT%@%d", sign, hours)
        } else {
            offset = String(format: "GMT%@%d:%02d", sign, hours, minutes)
        }
        _ = locale
        return "\(city) (\(offset))"
    }

    static func displayName(for zone: TimeZone, locale: Locale = .current) -> String {
        displayName(forIdentifier: zone.identifier, locale: locale)
    }
}

/// 任务语义日历：全天日界、重复展开等。
enum TaskCalendar {
    static func timeZone(forTaskTimezone identifier: String?) -> TimeZone {
        if let raw = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           raw.isEmpty == false,
           let zone = TimeZone(identifier: raw) {
            return zone
        }
        return AppDisplayTimeZone.effectiveTimeZone
    }

    static func calendar(forTaskTimezone identifier: String?) -> Calendar {
        AppDisplayTimeZone.calendar(for: timeZone(forTaskTimezone: identifier))
    }

    /// 全天：取任务时区下的 Y/M/D，再落到「显示时区」同名日历日（保证跨区同日）。
    static func allDayDisplayDay(dueDate: Date, taskTimezone: String?, displayCalendar: Calendar) -> Date {
        let taskCal = calendar(forTaskTimezone: taskTimezone)
        let ymd = taskCal.dateComponents([.year, .month, .day], from: dueDate)
        return displayCalendar.date(from: ymd) ?? displayCalendar.startOfDay(for: dueDate)
    }
}
