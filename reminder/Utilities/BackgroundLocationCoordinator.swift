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
        manager.distanceFilter = SupabaseLocationStateDataService.defaultMinUpdateDistanceMeters
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

    func setPausedForLiveMode(_ paused: Bool) {
        isPausedForLiveMode = paused
    }

    func applyStoredPreference() async {
        await setEnabled(BackgroundLocationPreferences.isEnabled)
    }

    func setEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: BackgroundLocationPreferences.storageKey)
        refreshAuthorizationNotice()
        print(
            "[LocationPersist] backgroundCoordinator setEnabled=\(enabled) "
                + "auth=\(manager.authorizationStatus.rawValue) "
                + "hasContext=\(householdId != nil && profileId != nil && locationStateService != nil)"
        )

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
            manager.requestWhenInUseAuthorization()
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
        Task { @MainActor in
            LastKnownDeviceLocation.record(location)
            await reportIfNeeded(location)
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
