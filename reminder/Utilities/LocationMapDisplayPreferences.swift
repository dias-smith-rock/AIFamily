import Foundation

/// 地图 Tab 上展示的最近位置点数量（仅影响 UI，不改变服务端 `location_states` 存储）。
enum LocationMapDisplayPreferences {
    static let displayCountStorageKey = "locationMapHistoryDisplayCount"

    static let defaultHistoryDisplayCount = 3
    /// `0` 表示不限制展示点数（云端 `locations` 亦不封顶）。
    static let unlimitedHistoryDisplayCount = 0
    static let historyDisplayCountOptions = [3, 5, 10, 20, unlimitedHistoryDisplayCount]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            displayCountStorageKey: defaultHistoryDisplayCount,
        ])
    }

    static var historyDisplayCount: Int {
        guard let stored = UserDefaults.standard.object(forKey: displayCountStorageKey) as? Int else {
            return defaultHistoryDisplayCount
        }
        return normalizedCount(stored)
    }

    static func setHistoryDisplayCount(_ count: Int) {
        UserDefaults.standard.set(normalizedCount(count), forKey: displayCountStorageKey)
    }

    static func isUnlimited(_ count: Int) -> Bool {
        count == unlimitedHistoryDisplayCount
    }

    static func normalizedCount(_ count: Int) -> Int {
        if isUnlimited(count) { return unlimitedHistoryDisplayCount }
        guard count > 0 else { return defaultHistoryDisplayCount }
        if historyDisplayCountOptions.contains(count) { return count }
        let finiteOptions = historyDisplayCountOptions.filter { isUnlimited($0) == false }
        return finiteOptions.min(by: { abs($0 - count) < abs($1 - count) })
            ?? defaultHistoryDisplayCount
    }

    /// `nil` 表示展示日期范围内全部点。
    static func visiblePrefixCount(_ count: Int) -> Int? {
        let normalized = normalizedCount(count)
        if isUnlimited(normalized) { return nil }
        return normalized
    }

    static func formattedCount(_ count: Int, locale: Locale) -> String {
        let entry: L10n.Entry = switch normalizedCount(count) {
        case unlimitedHistoryDisplayCount: L10n.Common.unlimited
        case 3: L10n.Common.count3
        case 5: L10n.Common.count5
        case 10: L10n.Common.count10
        case 20: L10n.Common.count20
        default: L10n.Common.count3
        }
        return entry.string(locale: locale)
    }
}
