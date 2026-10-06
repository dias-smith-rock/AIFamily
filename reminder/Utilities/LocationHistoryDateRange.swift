import Foundation

/// 定位 Tab 轨迹/列表筛选：按显示时区自然日截取已存储的 `recorded_at`（不请求更多历史）。
struct LocationHistoryDateRange: Equatable {
    enum Kind: String, CaseIterable, Equatable {
        case today
        case yesterday
        case last3Days
        case last7Days
        case last30Days
        case custom
    }

    var kind: Kind
    /// 自定义闭区间的自然日（仅 `kind == .custom` 使用）。
    var customStartDay: Date
    var customEndDay: Date

    static func today(now: Date = Date(), calendar: Calendar = AppDisplayTimeZone.calendar()) -> LocationHistoryDateRange {
        let day = calendar.startOfDay(for: now)
        return LocationHistoryDateRange(kind: .today, customStartDay: day, customEndDay: day)
    }

    func includesNow(_ now: Date = Date(), calendar: Calendar = AppDisplayTimeZone.calendar()) -> Bool {
        interval(now: now, calendar: calendar).contains(now)
    }

    /// 半开区间 `[start, end)`，`end` 为结束日的次日 0 点。
    func interval(now: Date = Date(), calendar: Calendar = AppDisplayTimeZone.calendar()) -> DateInterval {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86400)

        switch kind {
        case .today:
            return DateInterval(start: todayStart, end: tomorrow)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
            return DateInterval(start: yesterday, end: todayStart)
        case .last3Days:
            let start = calendar.date(byAdding: .day, value: -2, to: todayStart) ?? todayStart
            return DateInterval(start: start, end: tomorrow)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            return DateInterval(start: start, end: tomorrow)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
            return DateInterval(start: start, end: tomorrow)
        case .custom:
            let start = calendar.startOfDay(for: min(customStartDay, customEndDay))
            let endDay = calendar.startOfDay(for: max(customStartDay, customEndDay))
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay.addingTimeInterval(86400)
            return DateInterval(start: start, end: end)
        }
    }

    func chipTitle(locale: Locale, now: Date = Date(), calendar: Calendar = AppDisplayTimeZone.calendar()) -> String {
        switch kind {
        case .today:
            return AppLocalized.string(L10n.Common.today, locale: locale)
        case .yesterday:
            return AppLocalized.string(L10n.Location.historyYesterday, locale: locale)
        case .last3Days:
            return AppLocalized.string(L10n.Location.historyLast3Days, locale: locale)
        case .last7Days:
            return AppLocalized.string(L10n.Location.historyLast7Days, locale: locale)
        case .last30Days:
            return AppLocalized.string(L10n.Location.historyLast30Days, locale: locale)
        case .custom:
            let start = calendar.startOfDay(for: min(customStartDay, customEndDay))
            let end = calendar.startOfDay(for: max(customStartDay, customEndDay))
            let format = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(locale)
            if calendar.isDate(start, inSameDayAs: end) {
                return start.formatted(format)
            }
            return "\(start.formatted(format)) – \(end.formatted(format))"
        }
    }
}
