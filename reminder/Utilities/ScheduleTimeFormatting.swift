import Foundation

/// 日程 Tab 时间展示：固定 24 小时制，避免跟随系统 12/24 小时设置。
enum ScheduleTimeFormatting {
    private static func clockFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = AppDisplayTimeZone.calendar(for: timeZone)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    static func timelineClockTime(
        _ date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = AppDisplayTimeZone.effectiveTimeZone
    ) -> String {
        _ = locale
        return clockFormatter(timeZone: timeZone).string(from: date)
    }

    static func timelineClockRange(
        start: Date,
        end: Date,
        locale: Locale = .current,
        timeZone: TimeZone = AppDisplayTimeZone.effectiveTimeZone
    ) -> String {
        _ = locale
        let calendar = AppDisplayTimeZone.calendar(for: timeZone)
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        if startDay != endDay {
            return "00:00 – 23:59"
        }
        return "\(timelineClockTime(start, timeZone: timeZone)) – \(timelineClockTime(end, timeZone: timeZone))"
    }

    /// SwiftUI `DatePicker` 强制 24 小时滚轮（`-u-hc-h23`）。
    static func twentyFourHourLocale(basedOn locale: Locale) -> Locale {
        let normalizedIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if normalizedIdentifier.contains("-u-hc-") {
            return locale
        }
        return Locale(identifier: "\(normalizedIdentifier)-u-hc-h23")
    }
}
