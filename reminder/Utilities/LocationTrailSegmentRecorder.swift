import CoreLocation
import Foundation

/// 稀疏 `location_states` 写入（prepend 新点）时累积锚点，静止或退后台时上传 `location_trail_segments`。
/// 与 [LocationTrailCaptureCoordinator] 密采通道互补：本通道跟随用户位移/间隔门禁。
@MainActor
final class LocationTrailSegmentRecorder {
    static let shared = LocationTrailSegmentRecorder()

    /// 仅 replace 最新点持续超过此时长则 flush（与 plan 30min 对齐）。
    static let replaceOnlyFlushSeconds: TimeInterval = 30 * 60

    private var trailService: LocationTrailDataService?
    private var householdId: UUID?
    private var profileId: UUID?

    private var openWaypoints: [TrailWaypoint] = []
    private var segmentStartedAt: Date?
    private var lastReplaceOnlyAt: Date?

    private init() {}

    func configure(trailService: LocationTrailDataService) {
        self.trailService = trailService
    }

    func updateContext(householdId: UUID?, profileId: UUID?) {
        if self.householdId != householdId || self.profileId != profileId {
            Task { await flush(reason: "contextChanged") }
            resetOpenSegment()
        }
        self.householdId = householdId
        self.profileId = profileId
    }

    func resetOpenSegment() {
        openWaypoints.removeAll(keepingCapacity: false)
        segmentStartedAt = nil
        lastReplaceOnlyAt = nil
    }

    /// 在 `location_states` 成功写入后调用。
    func handlePersistOutcome(
        _ outcome: LocationPersistOutcome,
        coordinate: CLLocationCoordinate2D,
        recordedAt: Date = Date()
    ) async {
        guard let householdId, let profileId else { return }
        if LocationGhostPreferences.shouldSkipLocationUpload(householdId: householdId, profileId: profileId) {
            resetOpenSegment()
            return
        }

        switch outcome {
        case .persisted(let mode):
            switch mode {
            case .prependNewPoint:
                lastReplaceOnlyAt = nil
                appendWaypoint(
                    TrailWaypoint(coordinate: coordinate, recordedAt: recordedAt)
                )
            case .replaceLatestPoint:
                if openWaypoints.isEmpty == false {
                    lastReplaceOnlyAt = recordedAt
                }
            }
        case .skippedGhost:
            resetOpenSegment()
        case .skippedWithinThreshold, .skippedWithinInterval:
            if let lastReplaceOnlyAt,
               openWaypoints.count >= 2,
               Date().timeIntervalSince(lastReplaceOnlyAt) >= Self.replaceOnlyFlushSeconds {
                await flush(reason: "stationaryAfterReplace")
            }
        }
    }

    func flush(reason: String) async {
        guard openWaypoints.count >= 2,
              let householdId,
              let profileId,
              let trailService else {
            resetOpenSegment()
            return
        }
        if LocationGhostPreferences.shouldSkipLocationUpload(householdId: householdId, profileId: profileId) {
            resetOpenSegment()
            return
        }

        let started = segmentStartedAt ?? openWaypoints.first?.recordedAt ?? Date()
        let ended = openWaypoints.last?.recordedAt ?? Date()
        let simplified = TrailSimplifier.simplify(
            openWaypoints,
            toleranceMeters: max(200, LocationPersistPreferences.minUpdateDistanceMeters * 0.4),
            maxPoints: 32
        )
        resetOpenSegment()
        guard simplified.count >= 2 else { return }

        guard await NetworkMonitor.shared.isConnected else {
            #if DEBUG
            print("[LocationTrail] recorder flush deferred offline reason=\(reason)")
            #endif
            return
        }

        do {
            _ = try await trailService.uploadTrailSegment(
                householdId: householdId,
                entityId: profileId,
                startedAt: started,
                endedAt: ended,
                waypoints: simplified
            )
            #if DEBUG
            print("[LocationTrail] recorder uploaded reason=\(reason) points=\(simplified.count)")
            #endif
        } catch {
            #if DEBUG
            print("[LocationTrail] recorder upload failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func appendWaypoint(_ waypoint: TrailWaypoint) {
        if openWaypoints.isEmpty {
            segmentStartedAt = waypoint.recordedAt ?? Date()
        }
        if let last = openWaypoints.last, waypoint.distanceMeters(to: last) < 50 {
            return
        }
        openWaypoints.append(waypoint)
    }
}
