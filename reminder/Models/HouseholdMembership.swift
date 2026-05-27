import Foundation

// MARK: - 2. 家庭成员关系 (HouseholdMembership)
/// `userId` 为空表示影子成员（未注册账号、由管理员代建）。
/// 组织内展示名使用 `nickname`（千组织千面）；全局档案名见关联的 `family_profiles.name`。
/// - Note: `role` / `status` 暂用 `String?` 解码，规避枚举大小写不一致导致嵌套 JSON 整段静默丢失。
struct HouseholdMembership: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    var userId: UUID?
    /// 指向 `family_profiles.id`；嵌套查询与写入身份行时必填（由 RPC / 触发器 / 客户端保证）。
    var profileId: UUID?
    var role: String?
    var nickname: String?
    var status: String?
    var joinedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    /// 连表查询 `profile:family_profiles!profile_id(...)` 时嵌套返回；写入 membership 行时不携带。
    var profile: FamilyProfile? = nil

    init(
        id: UUID,
        householdId: UUID,
        userId: UUID?,
        profileId: UUID? = nil,
        role: String?,
        nickname: String?,
        status: String?,
        joinedAt: Date?,
        createdAt: Date,
        updatedAt: Date,
        profile: FamilyProfile? = nil
    ) {
        self.id = id
        self.householdId = householdId
        self.userId = userId
        self.profileId = profileId
        self.role = role
        self.nickname = nickname
        self.status = status
        self.joinedAt = joinedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.profile = profile
    }

    /// 与 `SupabaseCodec.makeDecoder()` 的 `convertFromSnakeCase` 一致：勿再写 `= "household_id"` 等显式 snake，
    /// 否则与全局解码策略冲突，出现 `keyNotFound("household_id")`。
    enum CodingKeys: String, CodingKey {
        case id
        case householdId
        case userId
        case profileId
        case role
        case nickname
        case status
        case joinedAt
        case createdAt
        case updatedAt
        case profile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeRequiredUUID(container: container, key: .id)
        householdId = try Self.decodeRequiredUUID(container: container, key: .householdId)
        userId = try Self.decodeOptionalUUID(container: container, key: .userId)
        profileId = try Self.decodeOptionalUUID(container: container, key: .profileId)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        joinedAt = try Self.decodeOptionalDate(container: container, key: .joinedAt)
        createdAt = try Self.decodeOptionalDate(container: container, key: .createdAt) ?? Date.distantPast
        updatedAt = try Self.decodeOptionalDate(container: container, key: .updatedAt) ?? Date.distantPast
        if let nestedProfile = try container.decodeIfPresent(FamilyProfile.self, forKey: .profile) {
            profile = nestedProfile
        } else if let nestedProfiles = try container.decodeIfPresent([FamilyProfile].self, forKey: .profile),
                  let first = nestedProfiles.first {
            profile = first
        } else {
            profile = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(householdId, forKey: .householdId)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(profileId, forKey: .profileId)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(nickname, forKey: .nickname)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(joinedAt.map(Self.formatDateForEncoding), forKey: .joinedAt)
        try container.encode(Self.formatDateForEncoding(createdAt), forKey: .createdAt)
        try container.encode(Self.formatDateForEncoding(updatedAt), forKey: .updatedAt)
    }

    private static func decodeRequiredUUID(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> UUID {
        if let uuid = try? container.decode(UUID.self, forKey: key) {
            return uuid
        }
        let raw = try container.decode(String.self, forKey: key)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Invalid UUID")
        }
        return uuid
    }

    private static func decodeOptionalUUID(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> UUID? {
        if let uuid = try? container.decodeIfPresent(UUID.self, forKey: key) {
            return uuid
        }
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return UUID(uuidString: raw)
    }

    private static func decodeRequiredDate(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date {
        if let date = try? container.decode(Date.self, forKey: key) {
            return date
        }
        let raw = try container.decode(String.self, forKey: key)
        guard let date = parseDate(raw) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Invalid datetime")
        }
        return date
    }

    private static func decodeOptionalDate(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return parseDate(raw)
    }

    private static func parseDate(_ raw: String) -> Date? {
        if let date = iso8601WithFractional.date(from: raw) {
            return date
        }
        if let date = iso8601NoFractional.date(from: raw) {
            return date
        }
        return nil
    }

    private static func formatDateForEncoding(_ value: Date) -> String {
        iso8601WithFractional.string(from: value)
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let iso8601NoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

extension HouseholdMembership {
    /// 小写、去空白后的 `role`，供 UI 与排序容错比对。
    var normalizedRole: String? {
        guard let role else { return nil }
        let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return trimmed.lowercased()
    }

    /// 小写、去空白后的 `status`。
    var normalizedStatus: String? {
        guard let status else { return nil }
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return trimmed.lowercased()
    }

    var parsedRole: MembershipRole? {
        guard let normalizedRole else { return nil }
        return MembershipRole(rawValue: normalizedRole)
    }

    var parsedStatus: MembershipStatus? {
        guard let normalizedStatus else { return nil }
        return MembershipStatus(rawValue: normalizedStatus)
    }

    func hasRole(_ target: MembershipRole) -> Bool {
        normalizedRole == target.rawValue
    }

    func isActiveMembership() -> Bool {
        normalizedStatus == MembershipStatus.active.rawValue
    }

    /// Mock / 写入路径：枚举 → 字符串。
    init(
        id: UUID,
        householdId: UUID,
        userId: UUID?,
        profileId: UUID? = nil,
        role: MembershipRole,
        nickname: String,
        status: MembershipStatus,
        joinedAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.init(
            id: id,
            householdId: householdId,
            userId: userId,
            profileId: profileId,
            role: role.rawValue,
            nickname: nickname,
            status: status.rawValue,
            joinedAt: joinedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// 有 membership 时优先 `nickname`；否则回退关联档案的 `name`。
    func displayName(linkedProfile: FamilyProfile?) -> String {
        let trimmedNickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedNickname.isEmpty == false {
            return trimmedNickname
        }
        if let linkedProfile {
            let profileName = linkedProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if profileName.isEmpty == false, profileName != String(localized: "Unnamed member") {
                return profileName
            }
        }
        return MemberDisplayName.unknownFallback
    }
}
