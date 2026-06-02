import CoreLocation
import Foundation

enum TaskCompletionLocationProvider {
    /// 单次读取当前位置；失败（含用户拒绝定位）时返回 `nil`，不阻塞打勾完成。
    static func currentSnapshot(completedBy: UUID) async -> TaskCompletionLocation? {
        await OneShotLocationFetcher().fetch(completedBy: completedBy)
    }
}

@MainActor
private final class OneShotLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<TaskCompletionLocation?, Never>?
    private var completedBy: UUID?

    func fetch(completedBy: UUID) async -> TaskCompletionLocation? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.completedBy = completedBy
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

    private func finish(with snapshot: TaskCompletionLocation?) {
        continuation?.resume(returning: snapshot)
        continuation = nil
        completedBy = nil
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
            guard let completedBy, let location = locations.last else {
                finish(with: nil)
                return
            }
            let snapshot = TaskCompletionLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                completedAt: Date(),
                completedBy: completedBy
            )
            finish(with: snapshot)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(with: nil)
        }
    }
}