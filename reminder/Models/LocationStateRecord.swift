import Foundation

/// `location_states` 表行；`entity_id` = **`household_memberships.id`**（非 user id）。
struct LocationStateRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let householdId: UUID
    /// 库列 `entity_id`（membership 主键）。
    let membershipId: UUID
    var currentLocation: LocationPayload?
    var historyLocation1: LocationPayload?
    var historyLocation2: LocationPayload?
    /// 默认 `false`：仅用户选择「保持隐藏」后为 `true`。
    var isGhostMode: Bool
    var updatedAt: Date
}

extension LocationStateRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case householdId
        case membershipId = "entity_id"
        case currentLocation
        case historyLocation1
        case historyLocation2
        case isGhostMode
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        membershipId = try container.decode(UUID.self, forKey: .membershipId)
        currentLocation = try container.decodeIfPresent(LocationPayload.self, forKey: .currentLocation)
        historyLocation1 = try container.decodeIfPresent(LocationPayload.self, forKey: .historyLocation1)
        historyLocation2 = try container.decodeIfPresent(LocationPayload.self, forKey: .historyLocation2)
        isGhostMode = try container.decodeIfPresent(Bool.self, forKey: .isGhostMode) ?? false
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
