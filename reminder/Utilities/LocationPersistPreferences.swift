import Foundation

/// 用户可配置的位置入库门禁：位移阈值与上报间隔（须同时满足才写入 `location_states`）。
enum LocationPersistPreferences {
    static let distanceStorageKey = "locationPersistMinDistanceMeters"
    static let intervalStorageKey = "locationPersistMinIntervalSeconds"

    static let defaultMinUpdateDistanceMeters: Double = 500
    static let defaultMinUpdateIntervalSeconds: TimeInterval = 15 * 60

    /// 设置页与服务端 RPC 允许的最低位移（米）。
    static let minimumConfigurableDistanceMeters: Double = 100
    /// 设置页与服务端 RPC 允许的最低上报间隔（秒）。
    static let minimumConfigurableIntervalSeconds: TimeInterval = 5 * 60

    static let distanceOptionsMeters: [Double] = [100, 200, 300, 500, 1_000, 2_000]
    static let intervalOptionsSeconds: [TimeInterval] = [
        minimumConfigurableIntervalSeconds,
        10 * 60,
        15 * 60,
        30 * 60,
        60 * 60,
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            distanceStorageKey: defaultMinUpdateDistanceMeters,
            intervalStorageKey: defaultMinUpdateIntervalSeconds,
        ])
    }

    static var minUpdateDistanceMeters: Double {
        let stored = UserDefaults.standard.object(forKey: distanceStorageKey) as? Double
            ?? UserDefaults.standard.double(forKey: distanceStorageKey)
        return normalizedDistance(stored)
    }

    static var minUpdateIntervalSeconds: TimeInterval {
        let stored = UserDefaults.standard.object(forKey: intervalStorageKey) as? Double
            ?? UserDefaults.standard.double(forKey: intervalStorageKey)
        return normalizedInterval(stored)
    }

    static func setMinUpdateDistanceMeters(_ meters: Double) {
        UserDefaults.standard.set(normalizedDistance(meters), forKey: distanceStorageKey)
    }

    static func setMinUpdateIntervalSeconds(_ seconds: TimeInterval) {
        UserDefaults.standard.set(normalizedInterval(seconds), forKey: intervalStorageKey)
    }

    static func normalizedDistance(_ meters: Double) -> Double {
        guard meters > 0 else { return defaultMinUpdateDistanceMeters }
        let clamped = max(meters, minimumConfigurableDistanceMeters)
        if distanceOptionsMeters.contains(clamped) { return clamped }
        return distanceOptionsMeters.min(by: { abs($0 - clamped) < abs($1 - clamped) })
            ?? defaultMinUpdateDistanceMeters
    }

    static func normalizedInterval(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds > 0 else { return defaultMinUpdateIntervalSeconds }
        let clamped = max(seconds, minimumConfigurableIntervalSeconds)
        if intervalOptionsSeconds.contains(clamped) { return clamped }
        return intervalOptionsSeconds.min(by: { abs($0 - clamped) < abs($1 - clamped) })
            ?? defaultMinUpdateIntervalSeconds
    }

    static func summaryValue(locale: Locale) -> String {
        let distance = formattedDistance(minUpdateDistanceMeters, locale: locale)
        let interval = formattedInterval(minUpdateIntervalSeconds, locale: locale)
        return "\(distance) · \(interval)"
    }

    static func formattedDistance(_ meters: Double, locale: Locale) -> String {
        if meters >= 1_000, meters.truncatingRemainder(dividingBy: 1_000) == 0 {
            let kilometers = Int(meters / 1_000)
            return String(
                format: AppLocalized.string("%lld 千米", locale: locale),
                locale: locale,
                kilometers
            )
        }
        return String(
            format: AppLocalized.string("%lld 米", locale: locale),
            locale: locale,
            Int(meters)
        )
    }

    static func formattedInterval(_ seconds: TimeInterval, locale: Locale) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes >= 60, totalMinutes % 60 == 0 {
            let hours = totalMinutes / 60
            return String(
                format: AppLocalized.string("%lld 小时", locale: locale),
                locale: locale,
                hours
            )
        }
        return String(
            format: AppLocalized.string("%lld分钟", locale: locale),
            locale: locale,
            totalMinutes
        )
    }
}
