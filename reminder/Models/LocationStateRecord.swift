import Foundation

/// `location_states` 表行（列名经 `SupabaseCodec` 与驼峰互转）。
struct LocationStateRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let householdId: UUID
    let membershipId: UUID
    var currentLocation: LocationPayload?
    var historyLocation1: LocationPayload?
    var historyLocation2: LocationPayload?
    var isGhostMode: Bool
    var updatedAt: Date
}
