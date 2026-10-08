import CoreLocation
import Foundation

/// 本机密采轨迹缓冲：不上云；flush 时交给简化器产出稀疏锚点。
@MainActor
final class OnDeviceTrailBuffer {
    static let shared = OnDeviceTrailBuffer()

    /// 相邻采样最小位移（米）。
    static let minSampleDistanceMeters: CLLocationDistance = 35
    /// 静止超过此时长则视为行程暂停，可 flush。
    static let stationaryFlushSeconds: TimeInterval = 3 * 60
    /// 即使持续移动，最长多久强制 flush 一段。
    static let maxSegmentDurationSeconds: TimeInterval = 12 * 60
    /// 单段缓冲硬上限，防止内存膨胀。
    static let maxBufferedPoints = 2_000
    /// flush 至少需要的原始点数。
    static let minPointsToFlush = 3

    private var points: [TrailWaypoint] = []
    private var segmentStartedAt: Date?
    private var lastAcceptedAt: Date?

    private init() {}

    var bufferedCount: Int { points.count }

    func reset() {
        points.removeAll(keepingCapacity: false)
        segmentStartedAt = nil
        lastAcceptedAt = nil
    }

    /// 接受密采点；返回是否应立即 flush（超时 / 点数触顶）。
    @discardableResult
    func append(_ location: CLLocation) -> Bool {
        let waypoint = TrailWaypoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            recordedAt: location.timestamp
        )

        if let last = points.last {
            guard waypoint.distanceMeters(to: last) >= Self.minSampleDistanceMeters else {
                lastAcceptedAt = location.timestamp
                return shouldForceFlush(now: location.timestamp)
            }
        } else {
            segmentStartedAt = location.timestamp
        }

        points.append(waypoint)
        lastAcceptedAt = location.timestamp

        if points.count > Self.maxBufferedPoints {
            points = Array(points.suffix(Self.maxBufferedPoints))
            if let first = points.first?.recordedAt {
                segmentStartedAt = first
            }
        }

        return shouldForceFlush(now: location.timestamp)
    }

    /// 若已静止足够久且有足够点，返回可上传的简化段；否则 nil。
    func flushIfStationary(now: Date = Date()) -> PendingTrailSegment? {
        guard let lastAcceptedAt, now.timeIntervalSince(lastAcceptedAt) >= Self.stationaryFlushSeconds else {
            return nil
        }
        return flush(reason: "stationary")
    }

    func flush(reason: String) -> PendingTrailSegment? {
        guard points.count >= Self.minPointsToFlush else {
            #if DEBUG
            print("[LocationTrail] flush skipped reason=\(reason) points=\(points.count)")
            #endif
            reset()
            return nil
        }

        let started = segmentStartedAt ?? points.first?.recordedAt ?? Date()
        let ended = points.last?.recordedAt ?? Date()
        let simplified = TrailSimplifier.simplify(points)
        #if DEBUG
        print(
            "[LocationTrail] flush reason=\(reason) raw=\(points.count) simplified=\(simplified.count) "
                + "duration=\(Int(ended.timeIntervalSince(started)))s"
        )
        #endif
        reset()
        guard simplified.count >= 2 else { return nil }
        return PendingTrailSegment(startedAt: started, endedAt: ended, waypoints: simplified)
    }

    private func shouldForceFlush(now: Date) -> Bool {
        if points.count >= Self.maxBufferedPoints { return true }
        guard let started = segmentStartedAt else { return false }
        return now.timeIntervalSince(started) >= Self.maxSegmentDurationSeconds
    }
}

struct PendingTrailSegment: Sendable {
    let startedAt: Date
    let endedAt: Date
    let waypoints: [TrailWaypoint]
}
