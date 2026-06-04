import CoreLocation
import Foundation

@MainActor
enum LocationStartupReporter {
    static func reportIfNeeded(
        householdId: UUID?,
        membershipId: UUID?,
        locationStateService: LocationStateDataService
    ) async {
        guard let householdId, let membershipId else { return }

        do {
            if let record = try await locationStateService.fetchLocationState(
                householdId: householdId,
                membershipId: membershipId
            ),
               LocationGhostPreferences.isEffectivelyGhost(
                databaseFlag: record.isGhostMode,
                membershipId: membershipId
               ) {
                return
            }

            guard let coordinate = await DeviceLocationFetcher.currentCoordinate() else { return }
            await reportCoordinate(
                householdId: householdId,
                membershipId: membershipId,
                coordinate: coordinate,
                locationStateService: locationStateService
            )
        } catch {
            #if DEBUG
            print("[LocationStartupReporter] report skipped: \(error.localizedDescription)")
            #endif
        }
    }

    static func reportCoordinate(
        householdId: UUID,
        membershipId: UUID,
        coordinate: CLLocationCoordinate2D,
        locationStateService: LocationStateDataService
    ) async {
        do {
            if let record = try await locationStateService.fetchLocationState(
                householdId: householdId,
                membershipId: membershipId
            ),
               LocationGhostPreferences.isEffectivelyGhost(
                databaseFlag: record.isGhostMode,
                membershipId: membershipId
               ) {
                return
            }

            let payload = LocationPayload(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )

            _ = try await locationStateService.reportCurrentLocationIfNeeded(
                householdId: householdId,
                membershipId: membershipId,
                coordinate: payload,
                minDistanceMeters: SupabaseLocationStateDataService.defaultMinUpdateDistanceMeters
            )
        } catch {
            #if DEBUG
            print("[LocationStartupReporter] report skipped: \(error.localizedDescription)")
            #endif
        }
    }
}
