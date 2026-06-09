import CoreLocation
import Foundation

@MainActor
enum LocationStartupReporter {
    private static let logPrefix = "[LocationPersist]"

    @discardableResult
    static func report(
        trigger: LocationPersistTrigger,
        householdId: UUID?,
        profileId: UUID?,
        locationStateService: LocationStateDataService
    ) async -> LocationPersistLogEntry? {
        guard let householdId, let profileId else {
            log(trigger: trigger, profileId: nil, coordinate: nil, outcome: .failed(reason: "missing household or profile"))
            return nil
        }

        do {
            print("\(logPrefix) trigger=\(trigger.rawValue) step=ghostCheck")
            let record = try? await locationStateService.fetchLocationState(
                householdId: householdId,
                profileId: profileId
            )
            if let record,
               LocationGhostPreferences.isEffectivelyGhost(
                databaseFlag: record.isGhostMode,
                profileId: profileId
               ) {
                let entry = LocationPersistLogEntry(
                    trigger: trigger,
                    profileId: profileId,
                    coordinate: nil,
                    outcome: .skippedGhost
                )
                log(entry: entry)
                return entry
            }

            print("\(logPrefix) trigger=\(trigger.rawValue) step=resolveCoordinate")
            guard let coordinate = await resolveCoordinate(for: trigger) else {
                let entry = LocationPersistLogEntry(
                    trigger: trigger,
                    profileId: profileId,
                    coordinate: nil,
                    outcome: .failed(reason: "no GPS fix (no cache, fetch timed out or denied)")
                )
                log(entry: entry)
                return entry
            }

            logCoordinateReadyForUpload(
                trigger: trigger,
                householdId: householdId,
                profileId: profileId,
                coordinate: coordinate
            )
            return await reportCoordinate(
                trigger: trigger,
                householdId: householdId,
                profileId: profileId,
                coordinate: coordinate,
                locationStateService: locationStateService
            )
        } catch {
            let entry = LocationPersistLogEntry(
                trigger: trigger,
                profileId: profileId,
                coordinate: nil,
                outcome: .failed(reason: error.localizedDescription)
            )
            log(entry: entry)
            return entry
        }
    }

    @discardableResult
    static func reportCoordinate(
        trigger: LocationPersistTrigger,
        householdId: UUID,
        profileId: UUID,
        coordinate: CLLocationCoordinate2D,
        locationStateService: LocationStateDataService
    ) async -> LocationPersistLogEntry {
        let payload = LocationPayload(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        do {
            if let record = try? await locationStateService.fetchLocationState(
                householdId: householdId,
                profileId: profileId
            ),
               LocationGhostPreferences.isEffectivelyGhost(
                databaseFlag: record.isGhostMode,
                profileId: profileId
               ) {
                let entry = LocationPersistLogEntry(
                    trigger: trigger,
                    profileId: profileId,
                    coordinate: coordinate,
                    outcome: .skippedGhost
                )
                log(entry: entry)
                return entry
            }

            let outcome = try await locationStateService.reportCurrentLocationIfNeeded(
                householdId: householdId,
                profileId: profileId,
                coordinate: payload,
                minDistanceMeters: LocationPersistPreferences.minUpdateDistanceMeters,
                minIntervalSeconds: LocationPersistPreferences.minUpdateIntervalSeconds
            )
            let entry = LocationPersistLogEntry(
                trigger: trigger,
                profileId: profileId,
                coordinate: coordinate,
                outcome: .fromService(outcome)
            )
            log(entry: entry)
            return entry
        } catch {
            let entry = LocationPersistLogEntry(
                trigger: trigger,
                profileId: profileId,
                coordinate: coordinate,
                outcome: .failed(reason: error.localizedDescription)
            )
            log(entry: entry)
            return entry
        }
    }

    private static func logCoordinateReadyForUpload(
        trigger: LocationPersistTrigger,
        householdId: UUID,
        profileId: UUID,
        coordinate: CLLocationCoordinate2D
    ) {
        print(
            "\(logPrefix) trigger=\(trigger.rawValue) step=upload "
                + "household=\(householdId.uuidString.prefix(8)) "
                + "profile=\(profileId.uuidString.prefix(8)) "
                + String(format: "lat=%.6f lng=%.6f", coordinate.latitude, coordinate.longitude)
        )
    }

    private static func resolveCoordinate(for trigger: LocationPersistTrigger) async -> CLLocationCoordinate2D? {
        if trigger == .appEnteringBackground {
            if let cached = LastKnownDeviceLocation.cachedCoordinate() {
                print(
                    "\(logPrefix) coordinate source=sessionCache age=\(LastKnownDeviceLocation.cacheAgeDescription())"
                )
                return cached
            }
            print("\(logPrefix) coordinate source=fetch timeout=2s (no session cache)")
            if let fetched = await DeviceLocationFetcher.currentCoordinate(timeoutSeconds: 2) {
                return fetched
            }
            return nil
        }

        if let fetched = await DeviceLocationFetcher.currentCoordinate() {
            return fetched
        }
        return LastKnownDeviceLocation.cachedCoordinate()
    }

    /// 兼容旧调用；等价于 `report(trigger: .appEnteredForeground, ...)`。
    static func reportIfNeeded(
        householdId: UUID?,
        profileId: UUID?,
        locationStateService: LocationStateDataService
    ) async {
        await report(
            trigger: .appEnteredForeground,
            householdId: householdId,
            profileId: profileId,
            locationStateService: locationStateService
        )
    }

    private static func log(entry: LocationPersistLogEntry) {
        print("\(logPrefix) \(entry.formattedLine)")
    }

    private static func log(
        trigger: LocationPersistTrigger,
        profileId: UUID?,
        coordinate: CLLocationCoordinate2D?,
        outcome: LocationPersistLogEntry.DisplayOutcome
    ) {
        let entry = LocationPersistLogEntry(
            trigger: trigger,
            profileId: profileId,
            coordinate: coordinate,
            outcome: outcome
        )
        log(entry: entry)
    }
}

struct LocationPersistLogEntry: Sendable {
    enum DisplayOutcome: Sendable {
        case persisted
        case skippedGhost
        case skippedWithinThreshold(distanceMeters: Double)
        case skippedWithinInterval(elapsedSeconds: Double)
        case failed(reason: String)

        static func fromService(_ outcome: LocationPersistOutcome) -> DisplayOutcome {
            switch outcome {
            case .persisted:
                return .persisted
            case .skippedGhost:
                return .skippedGhost
            case .skippedWithinThreshold(let distanceMeters):
                return .skippedWithinThreshold(distanceMeters: distanceMeters)
            case .skippedWithinInterval(let elapsedSeconds):
                return .skippedWithinInterval(elapsedSeconds: elapsedSeconds)
            }
        }
    }

    let trigger: LocationPersistTrigger
    let profileId: UUID?
    let coordinate: CLLocationCoordinate2D?
    let outcome: DisplayOutcome

    var formattedLine: String {
        let profile = profileId.map { $0.uuidString.prefix(8) } ?? "none"
        let coords: String
        if let coordinate {
            coords = String(format: "lat=%.6f lng=%.6f", coordinate.latitude, coordinate.longitude)
        } else {
            coords = "lat=— lng=—"
        }
        let result: String
        switch outcome {
        case .persisted:
            result = "outcome=persisted ✓"
        case .skippedGhost:
            result = "outcome=skipped ghost"
        case .skippedWithinThreshold(let distanceMeters):
            result = String(
                format: "outcome=skipped threshold moved=%.0fm need≥%.0fm",
                distanceMeters,
                LocationPersistPreferences.minUpdateDistanceMeters
            )
        case .skippedWithinInterval(let elapsedSeconds):
            result = String(
                format: "outcome=skipped interval elapsed=%.0fs need≥%.0fs",
                elapsedSeconds,
                LocationPersistPreferences.minUpdateIntervalSeconds
            )
        case .failed(let reason):
            result = "outcome=failed \(reason)"
        }
        return "trigger=\(trigger.rawValue) profile=\(profile) \(coords) \(result)"
    }
}
