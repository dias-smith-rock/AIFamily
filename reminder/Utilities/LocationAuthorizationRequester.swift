import CoreLocation
import Foundation

/// 进入位置 Tab 等场景：未授权时触发系统「使用期间」定位权限弹窗。
@MainActor
final class LocationAuthorizationRequester: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorizationRequester()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Bool, Never>?

    private override init() {
        super.init()
    }

    /// 已授权返回 `true`；`.notDetermined` 时弹出系统授权框；拒绝/受限返回 `false`。
    func requestWhenInUseIfNeeded() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                manager.delegate = self
                manager.requestWhenInUseAuthorization()
            }
        case .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func finish(granted: Bool) {
        continuation?.resume(returning: granted)
        continuation = nil
        manager.delegate = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard continuation != nil else { return }
            switch manager.authorizationStatus {
            case .notDetermined:
                return
            case .authorizedAlways, .authorizedWhenInUse:
                finish(granted: true)
            case .restricted, .denied:
                finish(granted: false)
            @unknown default:
                finish(granted: false)
            }
        }
    }
}
