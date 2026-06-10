import Foundation

/// 地图 Tab 上展示的最近位置点数量（仅影响 UI，不改变服务端 `location_states` 存储）。
enum LocationMapDisplayPreferences {
    static let displayCountStorageKey = "locationMapHistoryDisplayCount"

    static let defaultHistoryDisplayCount = 3
    static let historyDisplayCountOptions = [3, 5, 10, 20]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            displayCountStorageKey: defaultHistoryDisplayCount,
        ])
    }

    static var historyDisplayCount: Int {
        let stored = UserDefaults.standard.object(forKey: displayCountStorageKey) as? Int
            ?? UserDefaults.standard.integer(forKey: displayCountStorageKey)
        return normalizedCount(stored)
    }

    static func setHistoryDisplayCount(_ count: Int) {
        UserDefaults.standard.set(normalizedCount(count), forKey: displayCountStorageKey)
    }

    static func normalizedCount(_ count: Int) -> Int {
        guard count > 0 else { return defaultHistoryDisplayCount }
        if historyDisplayCountOptions.contains(count) { return count }
        return historyDisplayCountOptions.min(by: { abs($0 - count) < abs($1 - count) })
            ?? defaultHistoryDisplayCount
    }

    static func formattedCount(_ count: Int, locale: Locale) -> String {
        String(
            format: AppLocalized.string("%lld 个", locale: locale),
            locale: locale,
            normalizedCount(count)
        )
    }
}
