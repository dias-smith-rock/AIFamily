import CoreLocation
import Foundation

actor MockLocationStateDataService: LocationStateDataService {
    private var records: [LocationStateRecord] = []

    init(seedPreview: Bool = true) {
        if seedPreview {
            records = UserLocationState.previewHousehold.map { preview in
                LocationStateRecord(
                    databaseId: UUID(),
                    householdId: UUID(),
                    profileId: preview.id,
                    locations: preview.locations,
                    isGhostMode: preview.isGhostMode,
                    updatedAt: preview.lastUpdatedAt ?? Date()
                )
            }
        }
    }

    func fetchLocationStates(in householdId: UUID) async throws -> [LocationStateRecord] {
        _ = householdId
        return records
    }

    func fetchLocationState(householdId: UUID, profileId: UUID) async throws -> LocationStateRecord? {
        _ = householdId
        return records.first(where: { $0.profileId == profileId })
    }

    @discardableResult
    func reportCurrentLocationIfNeeded(
        householdId: UUID,
        profileId: UUID,
        coordinate: LocationPayload,
        minDistanceMeters: Double,
        minIntervalSeconds: TimeInterval
    ) async throws -> LocationPersistOutcome {
        if let index = records.firstIndex(where: { $0.profileId == profileId }) {
            var row = records[index]
            if LocationGhostPreferences.shouldSkipLocationUpload(householdId: householdId, profileId: profileId) {
                return .skippedGhost
            }
            let decision = LocationPersistWriteGate.writeDecision(
                newCoordinate: coordinate,
                storedLocations: row.locations,
                lastRecordUpdatedAt: row.updatedAt,
                minDistanceMeters: minDistanceMeters,
                minIntervalSeconds: minIntervalSeconds
            )
            switch decision {
            case .skip(let skipOutcome):
                return skipOutcome
            case .write(let writeMode):
                let battery = DeviceBatteryMonitor.readSnapshot()
                let stamped = coordinate.stampingDeviceSnapshotIfNeeded(
                    batteryLevel: battery.level,
                    isCharging: battery.isCharging
                )
                row.locations = LocationHistoryLimits.applyingWrite(
                    stamped,
                    to: row.locations,
                    mode: writeMode
                )
            }
            row.updatedAt = Date()
            records[index] = row
            return .persisted
        }
        records.append(
            LocationStateRecord(
                databaseId: UUID(),
                householdId: householdId,
                profileId: profileId,
                locations: {
                    let battery = DeviceBatteryMonitor.readSnapshot()
                    return [
                        coordinate.stampingDeviceSnapshotIfNeeded(
                            batteryLevel: battery.level,
                            isCharging: battery.isCharging
                        )
                    ]
                }(),
                isGhostMode: false,
                updatedAt: Date()
            )
        )
        return .persisted
    }

    func updateGhostMode(
        householdId: UUID,
        profileId: UUID,
        isGhostMode: Bool
    ) async throws -> LocationStateRecord {
        if let index = records.firstIndex(where: { $0.profileId == profileId }) {
            var row = records[index]
            row.isGhostMode = isGhostMode
            row.updatedAt = Date()
            records[index] = row
            return row
        }
        let row = LocationStateRecord(
            databaseId: UUID(),
            householdId: householdId,
            profileId: profileId,
            locations: [],
            isGhostMode: isGhostMode,
            updatedAt: Date()
        )
        records.append(row)
        return row
    }

    func replaceLocationsForDebug(
        householdId: UUID,
        profileId: UUID,
        locations: [LocationPayload],
        isGhostMode: Bool
    ) async throws {
        let now = Date()
        let row = LocationStateRecord(
            databaseId: records.first(where: { $0.profileId == profileId })?.databaseId ?? UUID(),
            householdId: householdId,
            profileId: profileId,
            locations: locations,
            isGhostMode: isGhostMode,
            updatedAt: now
        )
        if let index = records.firstIndex(where: { $0.profileId == profileId }) {
            records[index] = row
        } else {
            records.append(row)
        }
    }
}
