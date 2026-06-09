import CoreLocation
import Foundation

/// 模拟器定位统一限制在香港包络内，避免 Xcode 模拟位置或随机回退导致坐标满世界漂移。
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

    static func isWithinHongKong(_ coordinate: CLLocationCoordinate2D) -> Bool {
        latitudeRange.contains(coordinate.latitude) && longitudeRange.contains(coordinate.longitude)
    }

    static func clampToHongKong(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: min(max(coordinate.latitude, latitudeRange.lowerBound), latitudeRange.upperBound),
            longitude: min(max(coordinate.longitude, longitudeRange.lowerBound), longitudeRange.upperBound)
        )
    }

    /// 真机原样返回；模拟器限制在香港包络内，无效或越界时用默认点。
    static func normalized(_ coordinate: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
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
