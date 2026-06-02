import CoreLocation
import Foundation

enum DeviceLocationFetcher {
    /// 单次读取设备坐标；授权失败或定位失败时返回 `nil`。
    static func currentCoordinate() async -> CLLocationCoordinate2D? {
        await OneShotCoordinateFetcher().fetch()
    }
}

@MainActor
private final class OneShotCoordinateFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    func fetch() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            resumeWhenAuthorized()
        }
    }

    private func resumeWhenAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            finish(with: nil)
        }
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
        manager.delegate = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard continuation != nil else { return }
            resumeWhenAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            finish(with: locations.last?.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(with: nil)
        }
    }
}
