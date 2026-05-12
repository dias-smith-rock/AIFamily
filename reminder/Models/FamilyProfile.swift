import Foundation

/// `family_profiles` 行：展示名与是否已绑定登录账号（`user_id`）。
struct FamilyProfile: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    var name: String
    var userId: UUID?
    var avatarUrl: String? = nil
    var gender: String? = nil
    var birthDate: String? = nil
    var idCardNum: String? = nil
    var passportNum: String? = nil
    var permitNum: String? = nil
    var height: Double? = nil
    var weight: Double? = nil
    var school: String? = nil
    var grade: String? = nil

    /// 与 `SupabaseCodec` 的 snake 互转一致：标准列用驼峰枚举名；`other_id_1` 经策略映射为 `otherId1`。
    enum CodingKeys: String, CodingKey {
        case id
        case householdId
        case name
        case userId
        case avatarUrl
        case gender
        case birthDate
        case idCardNum
        case passportNum
        case permitNum
        case height
        case weight
        case school
        case grade
        case otherId1
        case otherId2
    }

    init(
        id: UUID,
        householdId: UUID,
        name: String,
        userId: UUID?,
        avatarUrl: String? = nil,
        gender: String? = nil,
        birthDate: String? = nil,
        idCardNum: String? = nil,
        passportNum: String? = nil,
        permitNum: String? = nil,
        height: Double? = nil,
        weight: Double? = nil,
        school: String? = nil,
        grade: String? = nil
    ) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.userId = userId
        self.avatarUrl = avatarUrl
        self.gender = gender
        self.birthDate = birthDate
        self.idCardNum = idCardNum
        self.passportNum = passportNum
        self.permitNum = permitNum
        self.height = height
        self.weight = weight
        self.school = school
        self.grade = grade
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeRequiredUUID(container: container, key: .id)
        householdId = try Self.decodeRequiredUUID(container: container, key: .householdId)
        name = (try? container.decode(String.self, forKey: .name)) ?? "未命名成员"
        userId = try Self.decodeOptionalUUID(container: container, key: .userId)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        birthDate = try container.decodeIfPresent(String.self, forKey: .birthDate)
        idCardNum = try container.decodeIfPresent(String.self, forKey: .idCardNum)
        passportNum = try container.decodeIfPresent(String.self, forKey: .passportNum)
            ?? container.decodeIfPresent(String.self, forKey: .otherId1)
        permitNum = try container.decodeIfPresent(String.self, forKey: .permitNum)
            ?? container.decodeIfPresent(String.self, forKey: .otherId2)
        height = try Self.decodeOptionalDouble(container: container, key: .height)
        weight = try Self.decodeOptionalDouble(container: container, key: .weight)
        school = try container.decodeIfPresent(String.self, forKey: .school)
        grade = try container.decodeIfPresent(String.self, forKey: .grade)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encodeIfPresent(idCardNum, forKey: .idCardNum)
        try container.encodeIfPresent(passportNum, forKey: .passportNum)
        try container.encodeIfPresent(permitNum, forKey: .permitNum)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(weight, forKey: .weight)
        try container.encodeIfPresent(school, forKey: .school)
        try container.encodeIfPresent(grade, forKey: .grade)
    }

    private static func decodeRequiredUUID(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> UUID {
        if let uuid = try? container.decode(UUID.self, forKey: key) {
            return uuid
        }
        let text = try container.decode(String.self, forKey: key)
        if let uuid = UUID(uuidString: text) {
            return uuid
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Invalid UUID format for \(key.rawValue)"
        )
    }

    private static func decodeOptionalUUID(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> UUID? {
        if let uuid = try? container.decodeIfPresent(UUID.self, forKey: key) {
            return uuid
        }
        guard let text = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return UUID(uuidString: text)
    }

    private static func decodeOptionalDouble(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(intValue)
        }
        if let text = try container.decodeIfPresent(String.self, forKey: key) {
            return Double(text)
        }
        return nil
    }
}

/// 新建托管角色（`user_id` 必须保持为 nil）时的资料草稿。
struct ManagedProfileDraft: Equatable {
    var name: String
    var avatarURL: String?
    var gender: String?
    var birthDate: Date?
    var idCardNum: String?
    var passportNum: String?
    var permitNum: String?
    var height: Double?
    var weight: Double?
    var school: String?
    var grade: String?
}
