import Foundation

enum LocationHistoryLimits {
    static let maxStoredCount = 20

    /// newest-first：新点 prepend，超出上限丢弃最旧条目。
    static func prepending(_ new: LocationPayload, to existing: [LocationPayload]) -> [LocationPayload] {
        Array([new] + existing).prefix(maxStoredCount).map { $0 }
    }
}

enum LocationUpdateDistanceGate {
    /// 与库中 `locations[0]`（newest-first 最新点）比较；无历史记录时允许首次写入。
    /// - Returns: 距离未达阈值时的跳过结果；`nil` 表示可以写入。
    static func skipOutcomeIfWithinThreshold(
        newCoordinate: LocationPayload,
        storedLocations: [LocationPayload],
        minDistanceMeters: Double
    ) -> LocationPersistOutcome? {
        guard let latestStored = storedLocations.first else { return nil }
        let movedMeters = newCoordinate.distanceMeters(to: latestStored)
        guard movedMeters < minDistanceMeters else { return nil }
        return .skippedWithinThreshold(distanceMeters: movedMeters)
    }
}
