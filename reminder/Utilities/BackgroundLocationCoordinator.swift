import Combine
import CoreLocation
import Foundation

/// 聚合定位后台引擎：在用户开启应用内开关且系统授予「始终」时，后台持续按距离阈值写入 `location_states`。
@MainActor
final class BackgroundLocationCoordinator: NSObject, ObservableObject {
    static let shared = BackgroundLocationCoordinator()

    @Published private(set) var needsAlwaysPermission = false

    private let manager = CLLocationManager()
    private var locationStateService: LocationStateDataService?
    private var householdId: UUID?
    private var profileId: UUID?
    private var isMonitoring = false
    private var isPausedForLiveMode = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = LocationPersistPreferences.minUpdateDistanceMeters
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
        manager.showsBackgroundLocationIndicator = true
    }

    func configure(locationStateService: LocationStateDataService) {
        self.locationStateService = locationStateService
    }

    func updateContext(householdId: UUID?, profileId: UUID?) {
        self.householdId = householdId
        self.profileId = profileId
    }

    var debugSnapshot: String {
        "monitoring=\(isMonitoring) auth=\(LocationAuthorizationRequester.statusName(manager.authorizationStatus))/\(manager.authorizationStatus.rawValue) household=\(householdId?.uuidString ?? "nil") profile=\(profileId?.uuidString ?? "nil") dataSvc=\(locationStateService != nil) pausedLive=\(isPausedForLiveMode) prefOn=\(BackgroundLocationPreferences.isEnabled) services=\(CLLocationManager.locationServicesEnabled())"
    }

    func setPausedForLiveMode(_ paused: Bool) {
        isPausedForLiveMode = paused
    }

    func applyStoredPreference() async {
        await setEnabled(BackgroundLocationPreferences.isEnabled)
    }

    private var lastEnabledLog = ""

    func setEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: BackgroundLocationPreferences.storageKey)
        refreshAuthorizationNotice()
        print(
            "[LocationPersist] backgroundCoordinator setEnabled=\(enabled) "
                + debugSnapshot
        )
        let logDetail = "enabled=\(enabled) \(debugSnapshot)"
        if logDetail != lastEnabledLog {
            lastEnabledLog = logDetail
            TrackedDevicePairingLogger.event("loc_bg_set_enabled", detail: logDetail)
        }

        guard enabled else {
            stopMonitoring()
            return
        }

        guard householdId != nil, profileId != nil, locationStateService != nil else {
            print("[LocationPersist] backgroundCoordinator skipped reason=missingContext")
            stopMonitoring()
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            // 延后到位置 Tab（`LocationAuthorizationRequester`）再弹系统授权，避免一进 App 就申请。
            print("[LocationPersist] backgroundCoordinator deferred reason=notDetermined")
            stopMonitoring()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            startForegroundStyleUpdatesIfPossible()
        case .authorizedAlways:
            startBackgroundMonitoring()
        case .restricted, .denied:
            stopMonitoring()
        @unknown default:
            stopMonitoring()
        }
    }

    func applyPersistPreferences() {
        manager.distanceFilter = LocationPersistPreferences.minUpdateDistanceMeters
        print(
            "[LocationPersist] backgroundCoordinator distanceFilter="
                + "\(Int(LocationPersistPreferences.minUpdateDistanceMeters))m"
        )
    }

    func stop() {
        stopMonitoring()
        householdId = nil
        profileId = nil
        needsAlwaysPermission = false
    }

    func handleAuthorizationChange() async {
        refreshAuthorizationNotice()
        guard BackgroundLocationPreferences.isEnabled else {
            stopMonitoring()
            return
        }
        guard householdId != nil, profileId != nil else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways:
            startBackgroundMonitoring()
        case .authorizedWhenInUse:
            startForegroundStyleUpdatesIfPossible()
        default:
            stopMonitoring()
        }
    }

    private func refreshAuthorizationNotice() {
        guard BackgroundLocationPreferences.isEnabled else {
            needsAlwaysPermission = false
            return
        }
        let status = manager.authorizationStatus
        needsAlwaysPermission = status == .authorizedWhenInUse
            || status == .denied
            || status == .restricted
    }

    private func startBackgroundMonitoring() {
        guard isMonitoring == false else {
            manager.allowsBackgroundLocationUpdates = true
            return
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
        isMonitoring = true
        print("[LocationPersist] backgroundCoordinator monitoring started mode=always")
    }

    private func startForegroundStyleUpdatesIfPossible() {
        guard isMonitoring == false else { return }
        manager.allowsBackgroundLocationUpdates = false
        manager.startUpdatingLocation()
        isMonitoring = true
        print("[LocationPersist] backgroundCoordinator monitoring started mode=whenInUseOnly")
    }

    private func stopMonitoring() {
        guard isMonitoring else {
            manager.allowsBackgroundLocationUpdates = false
            return
        }
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        isMonitoring = false
        print("[LocationPersist] backgroundCoordinator monitoring stopped")
    }

    private var lastImmediateReportAt: Date?

    /// 小孩机启动：授权后立刻取点并写入 `location_states`（不受位移/间隔阈值限制）。
    @discardableResult
    func reportImmediateLaunchLocation() async -> Date? {
        if let lastImmediateReportAt, Date().timeIntervalSince(lastImmediateReportAt) < 8 {
            TrackedDevicePairingLogger.event("loc_immediate_skip", detail: "throttled \(debugSnapshot)")
            return nil
        }
        guard let householdId, let profileId, let locationStateService else {
            TrackedDevicePairingLogger.event("loc_immediate_skip", detail: "missingContext \(debugSnapshot)")
            return nil
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            TrackedDevicePairingLogger.event(
                "loc_immediate_skip",
                detail: "auth=\(LocationAuthorizationRequester.statusName(manager.authorizationStatus)) \(debugSnapshot)"
            )
            return nil
        }
        lastImmediateReportAt = Date()
        TrackedDevicePairingLogger.event("loc_immediate_start", detail: debugSnapshot)
        let entry = await LocationStartupReporter.report(
            trigger: .appLaunched,
            householdId: householdId,
            profileId: profileId,
            locationStateService: locationStateService,
            bypassThrottle: true
        )
        let detail = entry.map { "outcome=\($0.formattedLine)" } ?? "nil"
        TrackedDevicePairingLogger.event("loc_immediate_done", detail: detail)
        if let entry, case .persisted = entry.outcome {
            return Date()
        }
        return nil
    }

    private func reportIfNeeded(_ location: CLLocation) async {
        guard isPausedForLiveMode == false else {
            #if DEBUG
            print("[LocationPersist] backgroundGPS skipped reason=liveModeActive")
            #endif
            return
        }
        guard let householdId, let profileId, let locationStateService else {
            #if DEBUG
            print("[LocationPersist] backgroundGPS skipped reason=missingContext")
            #endif
            return
        }

        await LocationStartupReporter.reportCoordinate(
            trigger: .backgroundContinuous,
            householdId: householdId,
            profileId: profileId,
            coordinate: location.coordinate,
            locationStateService: locationStateService
        )
    }
}

// MARK: - CLLocationManagerDelegate

extension BackgroundLocationCoordinator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            await handleAuthorizationChange()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let normalized = SimulatorLocationSupport.normalized(location)
        Task { @MainActor in
            LastKnownDeviceLocation.record(normalized)
            await reportIfNeeded(normalized)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        Task { @MainActor in
            print("[BackgroundLocationCoordinator] error: \(error.localizedDescription)")
        }
        #endif
    }
}
