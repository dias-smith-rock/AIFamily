import CoreLocation
import Foundation

/// 进入位置 Tab：未授权时触发系统「使用期间」定位权限弹窗。
/// 小孩机绑定成功后走 `requestAlwaysForTrackedDeviceIfNeeded()`：先 WhenInUse，再申请始终。
@MainActor
final class LocationAuthorizationRequester: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorizationRequester()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var requestGeneration = 0

    private override init() {
        super.init()
        manager.delegate = self
        TrackedDevicePairingLogger.event(
            "loc_requester_init",
            detail: Self.probeDetail(manager: manager, extra: "delegateSet")
        )
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func probeDetail(extra: String) -> String {
        Self.probeDetail(manager: manager, extra: extra)
    }

    /// 已授权返回 `true`；`.notDetermined` 时弹出系统授权框；拒绝/受限返回 `false`。
    func requestWhenInUseIfNeeded() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined:
            let status = await requestAuthorization { manager.requestWhenInUseAuthorization() }
            return status == .authorizedAlways || status == .authorizedWhenInUse
        case .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    enum TrackedDeviceEnsureResult: Equatable {
        case always
        case whenInUse
        case denied
        case restricted
        case servicesOff
        case notDetermined
    }

    /// 小孩机：能弹系统框就弹；已拒绝则返回，由 UI 引导去设置。
    /// 总开关关闭时仍要 `requestWhenInUseAuthorization`，否则系统设置里不会出现「位置」。
    func ensureTrackedDeviceAccess() async -> TrackedDeviceEnsureResult {
        TrackedDevicePairingLogger.event("loc_ensure_start", detail: Self.probeDetail(manager: manager, extra: "begin"))
        let servicesOn = CLLocationManager.locationServicesEnabled()
        switch manager.authorizationStatus {
        case .authorizedAlways:
            TrackedDevicePairingLogger.event("loc_ensure_result", detail: "alreadyAlways")
            return .always
        case .notDetermined:
            let whenInUse = await requestAuthorization { manager.requestWhenInUseAuthorization() }
            TrackedDevicePairingLogger.event(
                "loc_ensure_when_in_use_done",
                detail: "status=\(Self.statusName(whenInUse)) services=\(CLLocationManager.locationServicesEnabled())"
            )
            if CLLocationManager.locationServicesEnabled() == false {
                TrackedDevicePairingLogger.event("loc_ensure_result", detail: "servicesOffAfterPrompt")
                return .servicesOff
            }
            guard whenInUse == .authorizedWhenInUse || whenInUse == .authorizedAlways else {
                return mapResult(whenInUse)
            }
            if manager.authorizationStatus == .authorizedAlways {
                TrackedDevicePairingLogger.event("loc_ensure_result", detail: "alwaysAfterWhenInUse")
                return .always
            }
            let always = await requestAuthorization { manager.requestAlwaysAuthorization() }
            TrackedDevicePairingLogger.event("loc_ensure_result", detail: "afterAlwaysPrompt=\(Self.statusName(always))")
            return mapResult(always)
        case .authorizedWhenInUse:
            let always = await requestAuthorization { manager.requestAlwaysAuthorization() }
            TrackedDevicePairingLogger.event("loc_ensure_result", detail: "upgradeAlways=\(Self.statusName(always))")
            return mapResult(always)
        case .denied:
            if servicesOn == false {
                TrackedDevicePairingLogger.event("loc_ensure_result", detail: "deniedBecauseServicesOff")
                return .servicesOff
            }
            TrackedDevicePairingLogger.event("loc_ensure_result", detail: "deniedCannotReprompt")
            return .denied
        case .restricted:
            TrackedDevicePairingLogger.event("loc_ensure_result", detail: "restrictedCannotReprompt")
            return .restricted
        @unknown default:
            return .denied
        }
    }

    /// 小孩机绑定后：使用期间 → 始终。已始终则直接返回。
    @discardableResult
    func requestAlwaysForTrackedDeviceIfNeeded() async -> Bool {
        let result = await ensureTrackedDeviceAccess()
        return result == .always
    }

    private func mapResult(_ status: CLAuthorizationStatus) -> TrackedDeviceEnsureResult {
        switch status {
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whenInUse
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    private func requestAuthorization(_ request: () -> Void) async -> CLAuthorizationStatus {
        if continuation != nil {
            TrackedDevicePairingLogger.event(
                "loc_auth_busy",
                detail: "returnCurrent=\(Self.statusName(manager.authorizationStatus))"
            )
            return manager.authorizationStatus
        }
        let before = manager.authorizationStatus
        requestGeneration += 1
        let generation = requestGeneration
        TrackedDevicePairingLogger.event(
            "loc_auth_request",
            detail: "before=\(Self.statusName(before)) gen=\(generation)"
        )
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            request()
            if before != .notDetermined {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    guard self.requestGeneration == generation, self.continuation != nil else { return }
                    TrackedDevicePairingLogger.event(
                        "loc_auth_no_callback",
                        detail: "after=\(Self.statusName(self.manager.authorizationStatus)) gen=\(generation)"
                    )
                    self.finish(self.manager.authorizationStatus)
                }
            }
        }
    }

    private func finish(_ status: CLAuthorizationStatus) {
        continuation?.resume(returning: status)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            TrackedDevicePairingLogger.event(
                "loc_auth_changed",
                detail: "status=\(Self.statusName(status)) waiting=\(continuation != nil)"
            )
            guard continuation != nil, status != .notDetermined else { return }
            finish(status)
        }
    }

    static func probeDetail(manager: CLLocationManager, extra: String) -> String {
        let whenInUseKey = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil
        let alwaysKey = Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") != nil
        let accuracy: String
        if #available(iOS 14.0, *) {
            accuracy = manager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced"
        } else {
            accuracy = "n/a"
        }
        return [
            extra,
            "services=\(CLLocationManager.locationServicesEnabled())",
            "auth=\(statusName(manager.authorizationStatus))/\(manager.authorizationStatus.rawValue)",
            "accuracy=\(accuracy)",
            "plistWhenInUse=\(whenInUseKey)",
            "plistAlways=\(alwaysKey)",
        ].joined(separator: " ")
    }

    static func statusName(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "whenInUse"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }
}
