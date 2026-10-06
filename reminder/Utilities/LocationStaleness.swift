import Foundation

/// 家长地图：根据「最后上报时间」判断是否可能离线（分钟级，不承诺实时）。
enum LocationStaleness {
    /// 超过该时长无新点则展示「可能离线」。
    static let offlineThreshold: TimeInterval = 30 * 60

    static func isLikelyOffline(
        lastUpdatedAt: Date?,
        relativeTo now: Date = Date(),
        threshold: TimeInterval = offlineThreshold
    ) -> Bool {
        guard let lastUpdatedAt else { return true }
        return now.timeIntervalSince(lastUpdatedAt) > threshold
    }
}
