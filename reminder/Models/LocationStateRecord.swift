import Foundation

/// `location_states` 表行；`entity_id` = **`family_profiles.id`**（非 membership / user id）。
/// 表主键常为 `(household_id, entity_id)`，**无** `id` 列时 `databaseId` 为 nil。
struct LocationStateRecord: Identifiable, Equatable, Sendable {
    /// 若表有 `id` 列则解码；否则用 `profileId` 作为 `Identifiable.id`。
    let databaseId: UUID?
    let householdId: UUID
    /// 库列 `entity_id`（family_profiles 主键）。
    let profileId: UUID
    /// newest-first；`locations[0]` 为最新位置。
    var locations: [LocationPayload]
    /// 默认 `false`：用户开启「位置隐身」后为 `true`。
    var isGhostMode: Bool
    var updatedAt: Date

    var id: UUID { databaseId ?? profileId }

    var latestLocation: LocationPayload? { locations.first }

    var locationHistoryOldestFirst: [LocationPayload] { locations.reversed() }

    init(
        databaseId: UUID?,
        householdId: UUID,
        profileId: UUID,
        locations: [LocationPayload] = [],
        isGhostMode: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.databaseId = databaseId
        self.householdId = householdId
        self.profileId = profileId
        self.locations = locations
        self.isGhostMode = isGhostMode
        self.updatedAt = updatedAt
    }
}

extension LocationStateRecord: Codable {
    /// 与 PostgREST 列名一致；`entity_id` 在 Swift 侧解码为 `entityId` 再赋给 `profileId`。
    enum CodingKeys: String, CodingKey {
        case databaseId = "id"
        case householdId = "household_id"
        case entityId = "entity_id"
        case locations
        case currentLocation = "current_location"
        case historyLocation1 = "history_location_1"
        case historyLocation2 = "history_location_2"
        case isGhostMode = "is_ghost_mode"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        databaseId = Self.decodeOptionalUUID(from: container, forKey: .databaseId)
        householdId = try Self.decodeRequiredUUID(from: container, forKey: .householdId)
        profileId = try Self.decodeRequiredUUID(from: container, forKey: .entityId)
        locations = (try? container.decode([LocationPayload].self, forKey: .locations)) ?? []
        if locations.isEmpty {
            let legacy = [
                Self.decodeLenientLocation(from: container, forKey: .currentLocation),
                Self.decodeLenientLocation(from: container, forKey: .historyLocation1),
                Self.decodeLenientLocation(from: container, forKey: .historyLocation2),
            ].compactMap { $0 }
            locations = legacy
        }
        isGhostMode = (try? container.decode(Bool.self, forKey: .isGhostMode)) ?? false
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? Date.distantPast
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(databaseId, forKey: .databaseId)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(profileId, forKey: .entityId)
        try container.encode(locations, forKey: .locations)
        try container.encode(isGhostMode, forKey: .isGhostMode)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func decodeOptionalUUID(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> UUID? {
        if let uuid = try? container.decodeIfPresent(UUID.self, forKey: key) {
            return uuid
        }
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    private static func decodeRequiredUUID(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> UUID {
        if let uuid = try? container.decode(UUID.self, forKey: key) {
            return uuid
        }
        let raw = try container.decode(String.self, forKey: key)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid UUID string: \(raw)"
            )
        }
        return uuid
    }

    private static func decodeLenientLocation(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> LocationPayload? {
        if let payload = try? container.decodeIfPresent(LocationPayload.self, forKey: key) {
            return payload
        }
        return nil
    }
}
