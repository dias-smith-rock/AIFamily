import Foundation

enum LocationHistoryLimits {
    /// 客户端 fallback 写入时 `locations` 条数上限（与 Supabase RPC 策略对齐）。
    static let maxStoredLocationPoints = 180
    /// 丢弃早于该天数的点（与 Location Tab「最近 30 天」一致）。
    static let maxLocationAgeDays = 30

    /// newest-first：新点 prepend，不截断历史。
    static func prepending(_ new: LocationPayload, to existing: [LocationPayload]) -> [LocationPayload] {
        trimLocations([new] + existing)
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
            return trimLocations(replacingLatest(new, in: existing))
        }
    }

    static func trimLocations(_ locations: [LocationPayload], now: Date = Date()) -> [LocationPayload] {
        let calendar = Calendar.current
        let ageCutoff = calendar.date(byAdding: .day, value: -maxLocationAgeDays, to: now) ?? now
        var next = locations.filter { payload in
            guard let stamp = payload.recordedAt else { return true }
            return stamp >= ageCutoff
        }
        if next.count > maxStoredLocationPoints {
            next = Array(next.prefix(maxStoredLocationPoints))
        }
        return next
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
