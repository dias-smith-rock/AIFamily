import CoreLocation
import Foundation

enum DeviceLocationFetcher {
    /// 单次读取设备坐标；授权失败或定位失败时返回 `nil`（DEBUG 模拟器回退香港随机点）。
    static func currentCoordinate() async -> CLLocationCoordinate2D? {
        await OneShotCoordinateFetcher().fetch()
    }
}

#if DEBUG
private enum SimulatorHongKongFallback {
    /// 香港市区大致包络（九龙 / 港岛 / 新界南），每次调用独立随机。
    private static let latitudeRange = 22.26...22.45
    private static let longitudeRange = 114.00...114.25

    static var isEnabled: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static func randomCoordinate() -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: Double.random(in: latitudeRange),
            longitude: Double.random(in: longitudeRange)
        )
    }
}
#endif

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
        let resolved = resolveCoordinate(coordinate)
        continuation?.resume(returning: resolved)
        continuation = nil
        manager.delegate = nil
    }

    private func resolveCoordinate(_ coordinate: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        if let coordinate {
            return coordinate
        }
        #if DEBUG
        guard SimulatorHongKongFallback.isEnabled else { return nil }
        let fallback = SimulatorHongKongFallback.randomCoordinate()
        print("[DeviceLocationFetcher] simulator fallback → \(fallback.latitude), \(fallback.longitude)")
        return fallback
        #else
        return nil
        #endif
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
            #if DEBUG
            print("[DeviceLocationFetcher] requestLocation failed: \(error.localizedDescription)")
            #endif
            finish(with: nil)
        }
    }
}
