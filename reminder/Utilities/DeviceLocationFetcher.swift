import CoreLocation
import Foundation

enum DeviceLocationFetcher {
    /// 单次读取设备坐标；授权失败或定位失败时返回 `nil`（模拟器回退香港固定默认点）。
    static func currentCoordinate(timeoutSeconds: TimeInterval? = nil) async -> CLLocationCoordinate2D? {
        guard let timeoutSeconds, timeoutSeconds > 0 else {
            return await OneShotCoordinateFetcher().fetch()
        }

        return await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
            group.addTask { await OneShotCoordinateFetcher().fetch() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
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
            // 不在此处弹权限；由位置 Tab 的 `LocationAuthorizationRequester` 显式申请。
            finish(with: nil)
        default:
            finish(with: nil)
        }
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        let resolved = resolveCoordinate(coordinate)
        if let resolved {
            LastKnownDeviceLocation.record(latitude: resolved.latitude, longitude: resolved.longitude)
        }
        continuation?.resume(returning: resolved)
        continuation = nil
        manager.delegate = nil
    }

    private func resolveCoordinate(_ coordinate: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        let resolved = SimulatorLocationSupport.normalized(coordinate)
        #if DEBUG
        if SimulatorLocationSupport.isRunningOnSimulator, let resolved {
            if coordinate == nil {
                print("[DeviceLocationFetcher] simulator fallback → \(resolved.latitude), \(resolved.longitude)")
            } else if let coordinate, !SimulatorLocationSupport.isWithinHongKong(coordinate) {
                print("[DeviceLocationFetcher] simulator clamped → \(resolved.latitude), \(resolved.longitude)")
            }
        }
        #endif
        return resolved
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
