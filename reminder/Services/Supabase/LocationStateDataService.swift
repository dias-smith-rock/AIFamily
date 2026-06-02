import Foundation

protocol LocationStateDataService: Sendable {
    func fetchLocationStates(in householdId: UUID) async throws -> [LocationStateRecord]
    func fetchLocationState(householdId: UUID, membershipId: UUID) async throws -> LocationStateRecord?
    /// 非隐身且与现位距离 ≥ `minDistanceMeters` 时写入；过近则跳过。
    @discardableResult
    func reportCurrentLocationIfNeeded(
        householdId: UUID,
        membershipId: UUID,
        coordinate: LocationPayload,
        minDistanceMeters: Double
    ) async throws -> Bool
    func updateGhostMode(
        householdId: UUID,
        membershipId: UUID,
        isGhostMode: Bool
    ) async throws -> LocationStateRecord
}
