import Foundation

// MARK: - 2. 家庭成员关系 (HouseholdMembership)
/// `userId` 为空表示影子成员（未注册账号、由管理员代建）。
struct HouseholdMembership: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    var userId: UUID?
    /// 指向 `family_profiles.id`；嵌套查询与写入身份行时必填（由 RPC / 触发器 / 客户端保证）。
    var profileId: UUID?
    var role: MembershipRole
    var nickname: String
    var avatarUrl: String?
    var contactMethod: ContactMethod
    var phoneNumber: String?
    var email: String?
    var status: MembershipStatus
    var joinedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        householdId: UUID,
        userId: UUID?,
        profileId: UUID? = nil,
        role: MembershipRole,
        nickname: String,
        avatarUrl: String?,
        contactMethod: ContactMethod,
        phoneNumber: String?,
        email: String?,
        status: MembershipStatus,
        joinedAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.householdId = householdId
        self.userId = userId
        self.profileId = profileId
        self.role = role
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.contactMethod = contactMethod
        self.phoneNumber = phoneNumber
        self.email = email
        self.status = status
        self.joinedAt = joinedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
        case avatarUrl
        case contactMethod
        case phoneNumber
        case email
        case status
        case joinedAt
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeRequiredUUID(container: container, key: .id)
        householdId = try Self.decodeRequiredUUID(container: container, key: .householdId)
        userId = try Self.decodeOptionalUUID(container: container, key: .userId)
        profileId = try Self.decodeOptionalUUID(container: container, key: .profileId)
        role = try container.decode(MembershipRole.self, forKey: .role)
        nickname = try container.decode(String.self, forKey: .nickname)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        contactMethod = try container.decode(ContactMethod.self, forKey: .contactMethod)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        status = try container.decode(MembershipStatus.self, forKey: .status)
        joinedAt = try Self.decodeOptionalDate(container: container, key: .joinedAt)
        createdAt = try Self.decodeRequiredDate(container: container, key: .createdAt)
        updatedAt = try Self.decodeRequiredDate(container: container, key: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(householdId, forKey: .householdId)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(profileId, forKey: .profileId)
        try container.encode(role, forKey: .role)
        try container.encode(nickname, forKey: .nickname)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try container.encode(contactMethod, forKey: .contactMethod)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(status, forKey: .status)
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
