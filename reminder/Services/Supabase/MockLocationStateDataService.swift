import Foundation

actor MockLocationStateDataService: LocationStateDataService {
    private var records: [LocationStateRecord] = []

    init(seedPreview: Bool = true) {
        if seedPreview {
            records = UserLocationState.previewHousehold.map { preview in
                LocationStateRecord(
                    id: UUID(),
                    householdId: UUID(),
                    membershipId: preview.id,
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

    func fetchLocationState(householdId: UUID, membershipId: UUID) async throws -> LocationStateRecord? {
        _ = householdId
        return records.first(where: { $0.membershipId == membershipId })
    }

    @discardableResult
    func reportCurrentLocationIfNeeded(
        householdId: UUID,
        membershipId: UUID,
        coordinate: LocationPayload,
        minDistanceMeters: Double
    ) async throws -> Bool {
        _ = minDistanceMeters
        if let index = records.firstIndex(where: { $0.membershipId == membershipId }) {
            var row = records[index]
            if row.isGhostMode { return false }
            row.historyLocation2 = row.historyLocation1
            row.historyLocation1 = row.currentLocation
            row.currentLocation = coordinate
            row.updatedAt = Date()
            records[index] = row
            return true
        }
        records.append(
            LocationStateRecord(
                id: UUID(),
                householdId: householdId,
                membershipId: membershipId,
                currentLocation: coordinate,
                historyLocation1: nil,
                historyLocation2: nil,
                isGhostMode: false,
                updatedAt: Date()
            )
        )
        return true
    }

    func updateGhostMode(
        householdId: UUID,
        membershipId: UUID,
        isGhostMode: Bool
    ) async throws -> LocationStateRecord {
        if let index = records.firstIndex(where: { $0.membershipId == membershipId }) {
            var row = records[index]
            row.isGhostMode = isGhostMode
            row.updatedAt = Date()
            records[index] = row
            return row
        }
        let row = LocationStateRecord(
            id: UUID(),
            householdId: householdId,
            membershipId: membershipId,
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
