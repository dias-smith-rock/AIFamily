import CoreLocation
import Foundation

/// 展示/贴路前合并可连成一条路的相邻轨迹段（不改变服务端存储）。
enum LocationTrailSegmentMerger {
    /// 段与段之间最大空间间隔（米）；更小视为同一段行程的延续。
    static let maxSpatialGapMeters: CLLocationDistance = 600
    /// 上一段结束到下一段开始的最大时间间隔（秒）。
    static let maxTimeGapSeconds: TimeInterval = 20 * 60

    /// 输入任意顺序；输出 **endedAt 新 → 旧**（与 `trailSegmentsByProfileId` 一致）。
    static func mergeConnectable(_ segments: [LocationTrailSegment]) -> [LocationTrailSegment] {
        guard segments.count > 1 else { return segments }

        let chronological = segments.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
            return lhs.endedAt < rhs.endedAt
        }

        var merged: [LocationTrailSegment] = []
        for segment in chronological {
            if let last = merged.last, canConnect(previous: last, next: segment) {
                merged[merged.count - 1] = join(previous: last, next: segment)
            } else {
                merged.append(segment)
            }
        }

        return merged.sorted { $0.endedAt > $1.endedAt }
    }

    static func canConnect(previous: LocationTrailSegment, next: LocationTrailSegment) -> Bool {
        guard let prevEnd = previous.waypoints.last,
              let nextStart = next.waypoints.first else {
            return false
        }

        let gapSeconds = next.startedAt.timeIntervalSince(previous.endedAt)
        guard gapSeconds <= maxTimeGapSeconds else { return false }
        // 允许轻微时间重叠（时钟/上报顺序）
        guard gapSeconds >= -5 * 60 else { return false }

        return prevEnd.distanceMeters(to: nextStart) <= maxSpatialGapMeters
    }

    static func join(previous: LocationTrailSegment, next: LocationTrailSegment) -> LocationTrailSegment {
        var waypoints = previous.waypoints
        for point in next.waypoints {
            if let last = waypoints.last, last.distanceMeters(to: point) < 30 {
                continue
            }
            waypoints.append(point)
        }

        return LocationTrailSegment(
            id: previous.id,
            householdId: previous.householdId,
            entityId: previous.entityId,
            startedAt: previous.startedAt,
            endedAt: max(previous.endedAt, next.endedAt),
            waypoints: waypoints,
            pointCount: waypoints.count,
            createdAt: previous.createdAt ?? next.createdAt
        )
    }
}
