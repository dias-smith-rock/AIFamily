import Foundation

enum LocationHistoryLimits {
    static let maxStoredCount = 20

    /// newest-first：新点 prepend，超出上限丢弃最旧条目。
    static func prepending(_ new: LocationPayload, to existing: [LocationPayload]) -> [LocationPayload] {
        Array([new] + existing).prefix(maxStoredCount).map { $0 }
    }
}

enum LocationPersistWriteGate {
    /// 与库中 `locations[0]`（newest-first 最新点）比较；无历史记录时允许首次写入。
    /// 写入须**同时**满足：位移 ≥ `minDistanceMeters` 且距上次记录 ≥ `minIntervalSeconds`。
    /// - Returns: 未达门禁时的跳过结果；`nil` 表示可以写入。
    static func skipOutcomeIfNotEligible(
        newCoordinate: LocationPayload,
        storedLocations: [LocationPayload],
        lastRecordUpdatedAt: Date?,
        minDistanceMeters: Double,
        minIntervalSeconds: TimeInterval,
        now: Date = Date()
    ) -> LocationPersistOutcome? {
        guard let latestStored = storedLocations.first else { return nil }

        let movedMeters = newCoordinate.distanceMeters(to: latestStored)
        let distanceEligible = movedMeters >= minDistanceMeters

        let anchorDate = latestStored.recordedAt ?? lastRecordUpdatedAt ?? .distantPast
        let elapsedSeconds = now.timeIntervalSince(anchorDate)
        let intervalEligible = elapsedSeconds >= minIntervalSeconds

        if distanceEligible && intervalEligible { return nil }
        if distanceEligible == false {
            return .skippedWithinThreshold(distanceMeters: movedMeters)
        }
        return .skippedWithinInterval(elapsedSeconds: elapsedSeconds)
    }
}
