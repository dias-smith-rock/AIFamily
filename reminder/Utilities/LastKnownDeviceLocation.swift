import CoreLocation
import Foundation

/// 本会话内最近一次有效 GPS，供退后台入库使用（避免后台 `requestLocation` 挂起）。
@MainActor
enum LastKnownDeviceLocation {
    private static var coordinate: CLLocationCoordinate2D?
    private static var recordedAt: Date?

    static func record(_ location: CLLocation) {
        coordinate = SimulatorLocationSupport.normalized(location).coordinate
        recordedAt = Date()
    }

    static func record(latitude: Double, longitude: Double) {
        let raw = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        coordinate = SimulatorLocationSupport.normalized(raw) ?? raw
        recordedAt = Date()
    }

    static func cachedCoordinate(maxAgeSeconds: TimeInterval = 900) -> CLLocationCoordinate2D? {
        guard let coordinate, let recordedAt else { return nil }
        guard Date().timeIntervalSince(recordedAt) <= maxAgeSeconds else { return nil }
        return coordinate
    }

    static func cacheAgeDescription() -> String {
        guard let recordedAt else { return "none" }
        return String(format: "%.0fs ago", Date().timeIntervalSince(recordedAt))
    }
}
