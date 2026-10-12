import CoreLocation
import Foundation

#if DEBUG
/// DEBUG / Preview：本地贴路演示轨迹（不上云）。
enum LocationRoadSnapDemoData {
    static let previewCurrentUserMembershipId =
        UUID(uuidString: "A1000001-0000-4000-8000-000000000001")!

    /// 在 Location Tab 刷新后，若当前用户无 trail 段则注入演示折线锚点。
    static var injectWhenTrailEmpty: Bool {
        UserDefaults.standard.object(forKey: injectWhenTrailEmptyKey) as? Bool ?? true
    }

    static let injectWhenTrailEmptyKey = "locationRoadSnapDemoInjectWhenEmpty"

    static func setInjectWhenTrailEmpty(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: injectWhenTrailEmptyKey)
    }

    /// 以 `anchor`（通常为当前用户最新点）为终点，沿道路方向回溯若干锚点。
    static func makeSegments(
        householdId: UUID,
        profileId: UUID,
        anchor: CLLocationCoordinate2D,
        now: Date = Date()
    ) -> [LocationTrailSegment] {
        let waypoints = demoWaypoints(endingAt: anchor, now: now)
        guard waypoints.count >= 2 else { return [] }

        let started = waypoints.first?.recordedAt ?? now.addingTimeInterval(-45 * 60)
        let ended = waypoints.last?.recordedAt ?? now

        let primary = LocationTrailSegment(
            householdId: householdId,
            entityId: profileId,
            startedAt: started,
            endedAt: ended,
            waypoints: waypoints
        )

        // 第二段：稍早的一小段（测多段贴路）
        let earlierEnd = waypoints[0]
        let earlierStart = offsetCoordinate(earlierEnd.coordinate, dLat: -0.004, dLng: -0.003)
        let earlierWaypoints = [
            TrailWaypoint(
                latitude: earlierStart.latitude,
                longitude: earlierStart.longitude,
                recordedAt: started.addingTimeInterval(-35 * 60)
            ),
            TrailWaypoint(
                latitude: earlierEnd.latitude,
                longitude: earlierEnd.longitude,
                recordedAt: started.addingTimeInterval(-5 * 60)
            ),
        ]
        let secondary = LocationTrailSegment(
            householdId: householdId,
            entityId: profileId,
            startedAt: earlierWaypoints[0].recordedAt ?? started.addingTimeInterval(-35 * 60),
            endedAt: earlierWaypoints[1].recordedAt ?? started.addingTimeInterval(-5 * 60),
            waypoints: earlierWaypoints
        )

        return [primary, secondary]
    }

    /// Preview 固定：上海外滩 → 人民广场方向（锚点间距足够 MapKit 贴路）。
    static func previewShanghaiSegments(householdId: UUID, profileId: UUID, now: Date = Date()) -> [LocationTrailSegment] {
        let coords: [(Double, Double, TimeInterval)] = [
            (31.2233, 121.4608, -52 * 60),
            (31.2268, 121.4675, -40 * 60),
            (31.2295, 121.4728, -28 * 60),
            (31.2318, 121.4786, -16 * 60),
            (31.2304, 121.4737, -8 * 60),
        ]
        let waypoints = coords.map { lat, lng, offset in
            TrailWaypoint(latitude: lat, longitude: lng, recordedAt: now.addingTimeInterval(offset))
        }
        return [
            LocationTrailSegment(
                householdId: householdId,
                entityId: profileId,
                startedAt: waypoints[0].recordedAt ?? now.addingTimeInterval(-52 * 60),
                endedAt: waypoints.last?.recordedAt ?? now,
                waypoints: waypoints
            ),
        ]
    }

    private static func demoWaypoints(
        endingAt anchor: CLLocationCoordinate2D,
        now: Date
    ) -> [TrailWaypoint] {
        // 从终点向东北偏回溯 ~2.5km，模拟一段行车轨迹（香港/深圳/上海通用尺度）
        let steps: [(dLat: Double, dLng: Double, minutesAgo: TimeInterval)] = [
            (-0.018, -0.022, 48),
            (-0.012, -0.015, 36),
            (-0.008, -0.010, 24),
            (-0.004, -0.005, 12),
            (0, 0, 0),
        ]
        return steps.map { step in
            let lat = anchor.latitude + step.dLat
            let lng = anchor.longitude + step.dLng
            return TrailWaypoint(
                latitude: lat,
                longitude: lng,
                recordedAt: now.addingTimeInterval(-step.minutesAgo * 60)
            )
        }
    }

    private static func offsetCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        dLat: Double,
        dLng: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: coordinate.latitude + dLat,
            longitude: coordinate.longitude + dLng
        )
    }
}
#endif
