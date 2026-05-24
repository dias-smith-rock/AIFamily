import Foundation

/// `family_profiles` 行：展示名与可选 `user_id`（与 Auth 绑定，**不**用于判定是否为档案成员）。
/// `memberships` 可由服务端嵌套返回，或由客户端按 `profile_id` / `(user_id, household_id)` 与 `household_memberships` 合并写入。
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
    /// `family_profiles.email`：档案级联系邮箱（可与 Auth / membership 邮箱并存）。
    var email: String? = nil
    /// `family_profiles.mainphone`
    var mainPhone: String? = nil
    /// `family_profiles.secondphone`
    var secondPhone: String? = nil
    /// 与 `household_memberships` 的关联行（嵌套 JSON 或客户端 `mergingMembershipRows` 合并）。
    var memberships: [HouseholdMembership]? = nil

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
        case email
        case mainPhone = "mainphone"
        case secondPhone = "secondphone"
        case otherId1
        case otherId2
        case memberships
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
        grade: String? = nil,
        email: String? = nil,
        mainPhone: String? = nil,
        secondPhone: String? = nil,
        memberships: [HouseholdMembership]? = nil
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
        self.email = email
        self.mainPhone = mainPhone
        self.secondPhone = secondPhone
        self.memberships = memberships
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
        email = try container.decodeIfPresent(String.self, forKey: .email)
        mainPhone = try container.decodeIfPresent(String.self, forKey: .mainPhone)
        secondPhone = try container.decodeIfPresent(String.self, forKey: .secondPhone)
        memberships = try container.decodeIfPresent([HouseholdMembership].self, forKey: .memberships)
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
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(mainPhone, forKey: .mainPhone)
        try container.encodeIfPresent(secondPhone, forKey: .secondPhone)
        try container.encodeIfPresent(memberships, forKey: .memberships)
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

extension FamilyProfile {
    /// 嵌套结果中优先取 **活跃** 身份，否则取第一条（如待激活邀请）。
    var primaryMembership: HouseholdMembership? {
        guard let memberships, memberships.isEmpty == false else { return nil }
        return memberships.first { $0.status == .active } ?? memberships.first
    }

    /// 供 UI / 调试：`MembershipRole` 的原始字符串（如 `creator`、`admin`）；无身份时为 `nil`。
    var role: String? {
        primaryMembership?.role.rawValue
    }

    /// **档案成员（本地档案）** 的唯一判定：当前家庭下该档案是否关联到任意 `household_memberships`（含服务端嵌套或客户端合并结果）。
    var isLocalProfile: Bool {
        (memberships ?? []).isEmpty
    }

    /// 将 `household_memberships` 行并入档案：优先 **`profile_id == family_profiles.id`**，否则回退 **`(user_id, household_id)`**。
    /// 若嵌套查询已返回非空 `memberships`，则不再覆盖。
    static func mergingMembershipRows(
        _ profiles: [FamilyProfile],
        memberships: [HouseholdMembership]
    ) -> [FamilyProfile] {
        profiles.map { profile in
            if let existing = profile.memberships, existing.isEmpty == false {
                return profile
            }
            let byProfileId = memberships.filter { row in
                row.householdId == profile.householdId && row.profileId == profile.id
            }
            if byProfileId.isEmpty == false {
                var copy = profile
                copy.memberships = byProfileId
                return copy
            }
            guard let uid = profile.userId else {
                var copyNil = profile
                copyNil.memberships = nil
                return copyNil
            }
            let matched = memberships.filter { row in
                row.householdId == profile.householdId && row.userId == uid
            }
            var copy = profile
            copy.memberships = matched.isEmpty ? nil : matched
            return copy
        }
    }

    /// 当前组织内的 membership 昵称（嵌套或合并后）。
    var membershipNickname: String? {
        let trimmed = primaryMembership?.nickname.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `family_profiles.name` 档案全局名。
    var profileName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != "未命名成员" else { return nil }
        return trimmed
    }

    /// 列表 / 卡片统一展示名：有 membership → `nickname`；无 membership（档案成员）→ `name`。
    var displayName: String {
        MemberDisplayName.displayName(for: self, membership: primaryMembership)
    }

    func displayName(resolvingMembership membership: HouseholdMembership?) -> String {
        MemberDisplayName.displayName(for: self, membership: membership)
    }

    /// 档案上填写的联系邮箱；用于副标题等，不参与主展示名。
    var profileEmailForDisplay: String? {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return nil }
        return trimmed
    }

    /// 档案主手机号（非空时可参与列表脱敏展示）。
    var profileMainPhoneForDisplay: String? {
        let trimmed = mainPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return nil }
        return trimmed
    }

    static func uniqueMembershipsFlattened(from profiles: [FamilyProfile]) -> [HouseholdMembership] {
        var seen = Set<UUID>()
        var ordered: [HouseholdMembership] = []
        for profile in profiles {
            guard let list = profile.memberships else { continue }
            for m in list where seen.insert(m.id).inserted {
                ordered.append(m)
            }
        }
        return ordered
    }
}

/// 新建无 membership 的档案时的表单草稿（写入后由服务端生成 `family_profiles` 行）。
struct LocalProfileDraft: Equatable {
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
    var email: String?
    var mainPhone: String?
    var secondPhone: String?
}
