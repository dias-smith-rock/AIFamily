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
    private var membershipId: UUID?
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

    func updateContext(householdId: UUID?, membershipId: UUID?) {
        self.householdId = householdId
        self.membershipId = membershipId
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

        guard enabled else {
            stopMonitoring()
            return
        }

        guard householdId != nil, membershipId != nil, locationStateService != nil else {
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
        membershipId = nil
        needsAlwaysPermission = false
    }

    func handleAuthorizationChange() async {
        refreshAuthorizationNotice()
        guard BackgroundLocationPreferences.isEnabled else {
            stopMonitoring()
            return
        }
        guard householdId != nil, membershipId != nil else { return }

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
        #if DEBUG
        print("[BackgroundLocationCoordinator] monitoring started (always)")
        #endif
    }

    private func startForegroundStyleUpdatesIfPossible() {
        guard isMonitoring == false else { return }
        manager.allowsBackgroundLocationUpdates = false
        manager.startUpdatingLocation()
        isMonitoring = true
        #if DEBUG
        print("[BackgroundLocationCoordinator] monitoring started (when in use only)")
        #endif
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
        #if DEBUG
        print("[BackgroundLocationCoordinator] monitoring stopped")
        #endif
    }

    private func reportIfNeeded(_ location: CLLocation) async {
        guard isPausedForLiveMode == false else { return }
        guard let householdId, let membershipId, let locationStateService else { return }

        await LocationStartupReporter.reportCoordinate(
            householdId: householdId,
            membershipId: membershipId,
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
