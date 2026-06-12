import Foundation

enum LocationRelativeTimeFormatting {
    /// 地图标注轮播：「3 分钟前」「2 小时前」「1 天前」等。
    static func mapBadgeText(since date: Date, relativeTo now: Date = Date(), locale: Locale = .current) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        if interval < 45 {
            return L10n.Common.justNow.string(locale: locale)
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
