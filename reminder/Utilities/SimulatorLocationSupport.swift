import CoreLocation
import Foundation

/// 模拟器定位：默认限制在香港包络内；DEBUG 灌数可切换到圣何塞等演示锚点。
enum SimulatorLocationSupport {
    static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// 中环一带默认参考点（无 GPS 或越界时使用，固定不变）。
    static let defaultCoordinate = CLLocationCoordinate2D(latitude: 22.2819, longitude: 114.1580)

    private static let latitudeRange = 22.15...22.55
    private static let longitudeRange = 113.83...114.41

    #if DEBUG
    /// DEBUG Mock 激活后，模拟器「当前位置」固定到该锚点（避免被香港包络夹回）。
    private(set) static var debugMockAnchor: CLLocationCoordinate2D?

    static func activateDebugMockLocation(_ coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        debugMockAnchor = coordinate
    }

    static func clearDebugMockLocation() {
        debugMockAnchor = nil
    }
    #endif

    static func isWithinHongKong(_ coordinate: CLLocationCoordinate2D) -> Bool {
        latitudeRange.contains(coordinate.latitude) && longitudeRange.contains(coordinate.longitude)
    }

    static func clampToHongKong(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: min(max(coordinate.latitude, latitudeRange.lowerBound), latitudeRange.upperBound),
            longitude: min(max(coordinate.longitude, longitudeRange.lowerBound), longitudeRange.upperBound)
        )
    }

    /// 真机原样返回；模拟器默认限制在香港包络；DEBUG Mock 激活时返回演示锚点。
    static func normalized(_ coordinate: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        #if DEBUG
        if let debugMockAnchor {
            return debugMockAnchor
        }
        #endif
        guard isRunningOnSimulator else { return coordinate }
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else {
            return defaultCoordinate
        }
        guard isWithinHongKong(coordinate) else {
            return defaultCoordinate
        }
        return clampToHongKong(coordinate)
    }

    static func normalized(_ location: CLLocation) -> CLLocation {
        guard isRunningOnSimulator,
              let coordinate = normalized(location.coordinate) else {
            return location
        }
        guard coordinate.latitude != location.coordinate.latitude
            || coordinate.longitude != location.coordinate.longitude else {
            return location
        }
        return CLLocation(
            coordinate: coordinate,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: location.timestamp
        )
    }
}
