import Foundation

protocol LocationStateDataService: Sendable {
    func fetchLocationStates(in householdId: UUID) async throws -> [LocationStateRecord]
    func fetchLocationState(householdId: UUID, profileId: UUID) async throws -> LocationStateRecord?
    /// 非隐身且与 `locations[0]` 距离 ≥ `minDistanceMeters`、距上次记录 ≥ `minIntervalSeconds` 时写入；否则跳过。
    @discardableResult
    func reportCurrentLocationIfNeeded(
        householdId: UUID,
        profileId: UUID,
        coordinate: LocationPayload,
        minDistanceMeters: Double,
        minIntervalSeconds: TimeInterval
    ) async throws -> LocationPersistOutcome
    func updateGhostMode(
        householdId: UUID,
        profileId: UUID,
        isGhostMode: Bool
    ) async throws -> LocationStateRecord

    /// DEBUG 灌数：整表替换 `locations`（newest-first）。Release 实现可抛错。
    func replaceLocationsForDebug(
        householdId: UUID,
        profileId: UUID,
        locations: [LocationPayload],
        isGhostMode: Bool
    ) async throws
}
