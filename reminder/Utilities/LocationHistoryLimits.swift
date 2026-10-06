import Foundation

enum LocationHistoryLimits {
    /// newest-first：新点 prepend，不截断历史。
    static func prepending(_ new: LocationPayload, to existing: [LocationPayload]) -> [LocationPayload] {
        [new] + existing
    }

    /// newest-first：仅替换 `locations[0]`，历史轨迹不变（ABCD → EBCD）。
    static func replacingLatest(_ new: LocationPayload, in existing: [LocationPayload]) -> [LocationPayload] {
        guard existing.isEmpty == false else { return [new] }
        var next = existing
        next[0] = new
        return next
    }

    static func applyingWrite(
        _ new: LocationPayload,
        to existing: [LocationPayload],
        mode: LocationPersistWriteMode
    ) -> [LocationPayload] {
        switch mode {
        case .prependNewPoint:
            return prepending(new, to: existing)
        case .replaceLatestPoint:
            return replacingLatest(new, in: existing)
        }
    }
}

enum LocationPersistWriteMode: Sendable, Equatable {
    /// 位移与间隔均达标：新增一条位置记录。
    case prependNewPoint
    /// 间隔达标但位移未达标：覆盖最近一条位置记录。
    case replaceLatestPoint
}

enum LocationPersistWriteDecision: Sendable, Equatable {
    case skip(LocationPersistOutcome)
    case write(mode: LocationPersistWriteMode)
}

enum LocationPersistWriteGate {
    /// 与库中 `locations[0]`（newest-first 最新点）比较；无历史记录时允许首次写入。
    /// - 间隔未达标：跳过。
    /// - 间隔达标且位移达标：prepend 新点。
    /// - 间隔达标但位移未达标：替换 `locations[0]`。
    static func writeDecision(
        newCoordinate: LocationPayload,
        storedLocations: [LocationPayload],
        lastRecordUpdatedAt: Date?,
        minDistanceMeters: Double,
        minIntervalSeconds: TimeInterval,
        now: Date = Date()
    ) -> LocationPersistWriteDecision {
        guard let latestStored = storedLocations.first else {
            return .write(mode: .prependNewPoint)
        }

        let movedMeters = newCoordinate.distanceMeters(to: latestStored)
        let distanceEligible = movedMeters >= minDistanceMeters

        let anchorDate = latestStored.recordedAt ?? lastRecordUpdatedAt ?? .distantPast
        let elapsedSeconds = now.timeIntervalSince(anchorDate)
        let intervalEligible = elapsedSeconds >= minIntervalSeconds

        if intervalEligible == false {
            return .skip(.skippedWithinInterval(elapsedSeconds: elapsedSeconds))
        }
        if distanceEligible {
            return .write(mode: .prependNewPoint)
        }
        return .write(mode: .replaceLatestPoint)
    }
}
