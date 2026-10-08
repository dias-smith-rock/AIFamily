import Combine
import CoreLocation
import Foundation

/// 本机较高频采点 → 缓冲 → 简化后稀疏上报（与 `location_states` 并存）。
@MainActor
final class LocationTrailCaptureCoordinator: NSObject, ObservableObject {
    static let shared = LocationTrailCaptureCoordinator()

    private let manager = CLLocationManager()
    private var trailService: LocationTrailDataService?
    private var householdId: UUID?
    private var profileId: UUID?
    private var isMonitoring = false
    private var stationaryCheckTask: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = OnDeviceTrailBuffer.minSampleDistanceMeters
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    func configure(trailService: LocationTrailDataService) {
        self.trailService = trailService
    }

    func updateContext(householdId: UUID?, profileId: UUID?) {
        self.householdId = householdId
        self.profileId = profileId
    }

    func startIfNeeded() {
        guard householdId != nil, profileId != nil, trailService != nil else {
            stop(reason: "missingContext")
            return
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginMonitoring()
        default:
            stop(reason: "notAuthorized")
        }
    }

    func stop(reason: String = "manual") {
        guard isMonitoring || stationaryCheckTask != nil else { return }
        manager.stopUpdatingLocation()
        isMonitoring = false
        stationaryCheckTask?.cancel()
        stationaryCheckTask = nil
        #if DEBUG
        print("[LocationTrail] capture stopped reason=\(reason)")
        #endif
    }

    /// 退后台 / 登出前尽量 flush 当前段。
    func flushPending(reason: String) async {
        if let pending = OnDeviceTrailBuffer.shared.flush(reason: reason) {
            await upload(pending)
        }
    }

    private func beginMonitoring() {
        guard isMonitoring == false else { return }
        isMonitoring = true
        if BackgroundLocationPreferences.isEnabled,
           manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        } else {
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
        }
        manager.startUpdatingLocation()
        startStationaryChecker()
        #if DEBUG
        print("[LocationTrail] capture started distanceFilter=\(Int(OnDeviceTrailBuffer.minSampleDistanceMeters))m")
        #endif
    }

    private func startStationaryChecker() {
        stationaryCheckTask?.cancel()
        stationaryCheckTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard Task.isCancelled == false else { break }
                await self?.checkStationaryFlush()
            }
        }
    }

    private func checkStationaryFlush() async {
        guard let pending = OnDeviceTrailBuffer.shared.flushIfStationary() else { return }
        await upload(pending)
    }

    private func handleLocations(_ locations: [CLLocation]) async {
        guard let householdId, let profileId else { return }
        if LocationGhostPreferences.shouldSkipLocationUpload(householdId: householdId, profileId: profileId) {
            OnDeviceTrailBuffer.shared.reset()
            return
        }

        var shouldFlush = false
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 80 else { continue }
            if OnDeviceTrailBuffer.shared.append(location) {
                shouldFlush = true
            }
        }

        if shouldFlush, let pending = OnDeviceTrailBuffer.shared.flush(reason: "maxDurationOrCap") {
            await upload(pending)
        }
    }

    private func upload(_ pending: PendingTrailSegment) async {
        guard let householdId, let profileId, let trailService else { return }
        if LocationGhostPreferences.shouldSkipLocationUpload(householdId: householdId, profileId: profileId) {
            return
        }
        guard await NetworkMonitor.shared.isConnected else {
            #if DEBUG
            print("[LocationTrail] upload deferred offline points=\(pending.waypoints.count)")
            #endif
            return
        }

        do {
            _ = try await trailService.uploadTrailSegment(
                householdId: householdId,
                entityId: profileId,
                startedAt: pending.startedAt,
                endedAt: pending.endedAt,
                waypoints: pending.waypoints
            )
            #if DEBUG
            print("[LocationTrail] uploaded points=\(pending.waypoints.count)")
            #endif
        } catch {
            #if DEBUG
            print("[LocationTrail] upload failed: \(error.localizedDescription)")
            #endif
        }
    }
}

extension LocationTrailCaptureCoordinator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.startIfNeeded()
            default:
                self.stop(reason: "authorizationChanged")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            await self.handleLocations(locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("[LocationTrail] location error: \(error.localizedDescription)")
        #endif
    }
}
