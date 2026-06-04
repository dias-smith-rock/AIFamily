import Foundation

/// 从 `household_memberships` 出发联查 `households` 的入口页 DTO。
struct JoinedHousehold: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    let profileId: UUID?
    let role: String?
    let household: HouseholdBasicInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case householdId
        case profileId
        case role
        case household = "households"
    }

    init(
        id: UUID,
        householdId: UUID,
        profileId: UUID? = nil,
        role: String?,
        household: HouseholdBasicInfo?
    ) {
        self.id = id
        self.householdId = householdId
        self.profileId = profileId
        self.role = role
        self.household = household
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try Self.decodeHouseholdId(from: container)
        profileId = try container.decodeIfPresent(UUID.self, forKey: .profileId)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        household = try Self.decodeHouseholdEmbed(from: container)
    }

    private static func decodeHouseholdId(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> UUID {
        if let uuid = try? container.decode(UUID.self, forKey: .householdId) {
            return uuid
        }
        let raw = try container.decode(String.self, forKey: .householdId)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .householdId,
                in: container,
                debugDescription: "Invalid household_id UUID"
            )
        }
        return uuid
    }

    /// PostgREST 嵌套 `households` 可能为 `{}` 或 `[{}]`。
    private static func decodeHouseholdEmbed(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> HouseholdBasicInfo? {
        if let info = try container.decodeIfPresent(HouseholdBasicInfo.self, forKey: .household) {
            return info
        }
        if let list = try container.decodeIfPresent([HouseholdBasicInfo].self, forKey: .household) {
            return list.first
        }
        return nil
    }
}

struct HouseholdBasicInfo: Codable, Equatable {
    let id: UUID
    let name: String
    let status: String?
    let isPremium: Bool?

    init(id: UUID, name: String, status: String?, isPremium: Bool? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.isPremium = isPremium
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeUUID(from: container, key: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? String(localized: "未命名群组")
        status = try container.decodeIfPresent(String.self, forKey: .status)
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case isPremium
    }

    private static func decodeUUID(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> UUID {
        if let uuid = try? container.decode(UUID.self, forKey: key) {
            return uuid
        }
        let raw = try container.decode(String.self, forKey: key)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid UUID"
            )
        }
        return uuid
    }

    var normalizedStatus: String? {
        guard let status else { return nil }
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return trimmed.lowercased()
    }

    var isArchivedOrDeleted: Bool {
        guard let normalizedStatus else { return false }
        return normalizedStatus == HouseholdStatus.deleted.rawValue
            || normalizedStatus == "disbanded"
            || normalizedStatus == HouseholdStatus.suspended.rawValue
    }
}

extension JoinedHousehold {
    var displayHouseholdName: String {
        let trimmed = household?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(localized: "未命名群组") : trimmed
    }

    var normalizedRole: String? {
        guard let role else { return nil }
        let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return trimmed.lowercased()
    }

    var roleDisplayTitle: String {
        guard let normalizedRole,
              let parsed = MembershipRole(rawValue: normalizedRole) else {
            return MembershipRole.member.displayTitle
        }
        return parsed.displayTitle
    }

    var isSelectable: Bool {
        household != nil && household?.isArchivedOrDeleted == false
    }
}
