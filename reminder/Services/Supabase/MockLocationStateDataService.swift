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
                    currentLocation: preview.currentLocation,
                    historyLocation1: preview.historyLocation1,
                    historyLocation2: preview.historyLocation2,
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
        minDistanceMeters: Double
    ) async throws -> LocationPersistOutcome {
        if let index = records.firstIndex(where: { $0.profileId == profileId }) {
            var row = records[index]
            if row.isGhostMode { return .skippedGhost }
            if let current = row.currentLocation {
                let moved = current.distanceMeters(to: coordinate)
                if moved < minDistanceMeters {
                    return .skippedWithinThreshold(distanceMeters: moved)
                }
            }
            row.historyLocation2 = row.historyLocation1
            row.historyLocation1 = row.currentLocation
            let battery = DeviceBatteryMonitor.readSnapshot()
            row.currentLocation = coordinate.stampingDeviceSnapshotIfNeeded(
                batteryLevel: battery.level,
                isCharging: battery.isCharging
            )
            row.updatedAt = Date()
            records[index] = row
            return .persisted
        }
        records.append(
            LocationStateRecord(
                databaseId: UUID(),
                householdId: householdId,
                profileId: profileId,
                currentLocation: {
                    let battery = DeviceBatteryMonitor.readSnapshot()
                    return coordinate.stampingDeviceSnapshotIfNeeded(
                        batteryLevel: battery.level,
                        isCharging: battery.isCharging
                    )
                }(),
                historyLocation1: nil,
                historyLocation2: nil,
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
            currentLocation: nil,
            historyLocation1: nil,
            historyLocation2: nil,
            isGhostMode: isGhostMode,
            updatedAt: Date()
        )
        records.append(row)
        return row
    }
}
