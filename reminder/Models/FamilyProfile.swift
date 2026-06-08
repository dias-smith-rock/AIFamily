import Foundation

/// `family_profiles` 行：展示名与可选 `user_id`（与 Auth 绑定）。
/// 真实注册用户为**全局档案**（`household_id == nil`）；虚拟成员档案仍绑定 `household_id`。
/// `householdMemberships` 由 PostgREST 嵌套或客户端从 `household_memberships` 合并。
struct FamilyProfile: Identifiable, Codable, Equatable {
    let id: UUID
    /// 全局档案为 `nil`；仅虚拟/组织内档案有值。
    let householdId: UUID?
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
    /// 档案 `contact_method`（若库表有该列）；与 email / mainPhone 并存。
    var contactMethod: String? = nil
    /// 档案 `created_at` 原始字符串（连表 select 宽容解码，避免 Date 格式差异导致整表失败）。
    var profileCreatedAt: String? = nil
    /// 档案 `updated_at` 原始字符串。
    var profileUpdatedAt: String? = nil
    /// 嵌套 `household_memberships`（Left Join；虚拟成员为 `[]` 或 `nil`）。
    var householdMemberships: [HouseholdMembership]? = nil

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
        case contactMethod
        case profileCreatedAt = "createdAt"
        case profileUpdatedAt = "updatedAt"
        case otherId1
        case otherId2
        case householdMemberships
        /// 旧缓存 / 历史 alias `memberships:household_memberships!profile_id`
        case legacyMemberships = "memberships"
    }

    init(
        id: UUID,
        householdId: UUID?,
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
        contactMethod: String? = nil,
        profileCreatedAt: String? = nil,
        profileUpdatedAt: String? = nil,
        householdMemberships: [HouseholdMembership]? = nil
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
        self.contactMethod = contactMethod
        self.profileCreatedAt = profileCreatedAt
        self.profileUpdatedAt = profileUpdatedAt
        self.householdMemberships = householdMemberships
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeRequiredUUID(container: container, key: .id)
        householdId = try Self.decodeOptionalUUID(container: container, key: .householdId)
        name = (try? container.decode(String.self, forKey: .name)) ?? String(localized: "未命名成员")
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
        contactMethod = try container.decodeIfPresent(String.self, forKey: .contactMethod)
        profileCreatedAt = Self.decodeOptionalTimestampString(container: container, key: .profileCreatedAt)
        profileUpdatedAt = Self.decodeOptionalTimestampString(container: container, key: .profileUpdatedAt)
        if let nested = try container.decodeIfPresent([HouseholdMembership].self, forKey: .householdMemberships) {
            householdMemberships = nested
        } else if let single = try container.decodeIfPresent(HouseholdMembership.self, forKey: .householdMemberships) {
            householdMemberships = [single]
        } else if let legacy = try container.decodeIfPresent([HouseholdMembership].self, forKey: .legacyMemberships) {
            householdMemberships = legacy
        } else if let legacySingle = try container.decodeIfPresent(HouseholdMembership.self, forKey: .legacyMemberships) {
            householdMemberships = [legacySingle]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if let householdId {
            try container.encode(householdId, forKey: .householdId)
        } else {
            try container.encodeNil(forKey: .householdId)
        }
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
        try container.encodeIfPresent(contactMethod, forKey: .contactMethod)
        try container.encodeIfPresent(profileCreatedAt, forKey: .profileCreatedAt)
        try container.encodeIfPresent(profileUpdatedAt, forKey: .profileUpdatedAt)
        try container.encodeIfPresent(householdMemberships, forKey: .householdMemberships)
    }

    private static func decodeOptionalTimestampString(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return text
        }
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return ISO8601DateFormatter().string(from: date)
        }
        return nil
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
    /// 嵌套或客户端合并后的 membership 行（读写别名，便于合并逻辑复用）。
    var memberships: [HouseholdMembership]? {
        get { householdMemberships }
        set { householdMemberships = newValue }
    }

    /// 嵌套结果中优先取 **活跃** 身份，否则取第一条（如待激活邀请）。
    var primaryMembership: HouseholdMembership? {
        guard let householdMemberships, householdMemberships.isEmpty == false else { return nil }
        return householdMemberships.first { $0.isActiveMembership() } ?? householdMemberships.first
    }

    /// 供 UI / 调试：小写 `role` 字符串（如 `creator`）；无身份时为 `nil`。
    var role: String? {
        currentRole
    }

    /// 当前组织内身份角色（全小写）；UI 判定 `== "creator"` 时使用。
    var currentRole: String? {
        householdMemberships?.first?.normalizedRole
    }

    /// 由 `currentRole` 解析出的枚举（大小写容错）。
    var currentMembershipRole: MembershipRole? {
        guard let currentRole else { return nil }
        return MembershipRole(rawValue: currentRole)
    }

    /// **虚拟档案**：组织内创建、无登录账号（`household_id` 有值且 `user_id` 为空）。
    var isVirtualUser: Bool {
        userId == nil && householdId != nil
    }

    /// **虚拟成员**：与 `isVirtualUser` 同义，保留旧命名以兼容既有调用。
    var isLocalProfile: Bool {
        isVirtualUser
    }

    /// 是否为跨组织复用的全局注册用户档案。
    var isGlobalRegisteredProfile: Bool {
        userId != nil && householdId == nil
    }

    /// 将扁平 `household_memberships` 并入档案（Left Join 补全）：`profile_id == family_profiles.id` 或 `(user_id, household_id)`。
    /// 扁平 `members` 为权威来源：嵌套为空或 `fetchProfiles` 返回 `[]` 时仍须写入 `householdMemberships`。
    static func mergingMembershipRows(
        _ profiles: [FamilyProfile],
        memberships: [HouseholdMembership]
    ) -> [FamilyProfile] {
        profiles.map { profile in
            profile.attachingMemberships(from: memberships)
        }
    }

    /// 与档案匹配的扁平 membership 行（`profile_id` 优先，其次 `user_id`）。
    static func matchingMemberships(
        for profile: FamilyProfile,
        in memberships: [HouseholdMembership]
    ) -> [HouseholdMembership] {
        let byProfileId = memberships.filter { $0.profileId == profile.id }
        if byProfileId.isEmpty == false { return byProfileId }
        if let profileHouseholdId = profile.householdId {
            let sameHousehold = memberships.filter { $0.householdId == profileHouseholdId }
            if let uid = profile.userId {
                let byUser = sameHousehold.filter { $0.userId == uid }
                if byUser.isEmpty == false { return byUser }
            }
            return []
        }
        if let uid = profile.userId {
            return memberships.filter { $0.userId == uid }
        }
        return []
    }

    /// 将匹配到的 membership 写入副本；`explicitFallback` 在无法匹配时强制挂载（如 creator 兜底）。
    func attachingMemberships(
        from memberships: [HouseholdMembership],
        explicitFallback: [HouseholdMembership]? = nil
    ) -> FamilyProfile {
        let matched = Self.matchingMemberships(for: self, in: memberships)
        let resolved = matched.isEmpty ? (explicitFallback ?? householdMemberships) : matched
        guard let resolved, resolved.isEmpty == false else { return self }
        var copy = self
        copy.householdMemberships = resolved
        return copy
    }

    /// `fetchProfiles` 不可用时的最小档案占位（必须携带 `householdMemberships`）。
    static func syntheticPlaceholder(
        profileId: UUID,
        householdId: UUID?,
        userId: UUID?,
        name: String,
        memberships: [HouseholdMembership]
    ) -> FamilyProfile {
        FamilyProfile(
            id: profileId,
            householdId: householdId,
            name: name,
            userId: userId,
            householdMemberships: memberships
        )
    }

    static func syntheticPlaceholder(
        from membership: HouseholdMembership,
        profileId: UUID,
        relatedMemberships: [HouseholdMembership]
    ) -> FamilyProfile {
        let trimmed = membership.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = trimmed.isEmpty ? MemberDisplayName.unknownFallback : trimmed
        return syntheticPlaceholder(
            profileId: profileId,
            householdId: membership.householdId,
            userId: membership.userId,
            name: displayName,
            memberships: relatedMemberships
        )
    }

    /// 千组织千面：优先 `household_memberships[0].nickname` → 回退 `family_profiles.name` → 兜底。
    var displayName: String {
        if let list = householdMemberships,
           let firstMembership = list.first {
            let nickname = firstMembership.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if nickname.isEmpty == false {
                return GuestSessionStore.displaySelfName(nickname)
            }
        }
        let profileName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if profileName.isEmpty == false, profileName != String(localized: "未命名成员") {
            return GuestSessionStore.displaySelfName(profileName)
        }
        return MemberDisplayName.unknownFallback
    }

    /// 当前组织内嵌套 membership 的有效 nickname（若有）。
    var membershipNickname: String? {
        guard let first = householdMemberships?.first else { return nil }
        let trimmed = first.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `family_profiles.name` 档案全局名。
    var profileName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != String(localized: "未命名成员") else { return nil }
        return trimmed
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

    /// 档案备用手机号。
    var profileSecondPhoneForDisplay: String? {
        let trimmed = secondPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return nil }
        return trimmed
    }

    /// 列表卡片第二行：主号 → 备用号 → 邮箱；均无则 `nil`。
    var displayContact: String? {
        if let main = profileMainPhoneForDisplay { return main }
        if let second = profileSecondPhoneForDisplay { return second }
        if let email = profileEmailForDisplay { return email }
        return nil
    }

    /// 第二行展示的是否为手机号（用于脱敏与眼睛按钮）。
    var displayContactIsPhoneNumber: Bool {
        guard let contact = displayContact else { return false }
        return contact == profileMainPhoneForDisplay || contact == profileSecondPhoneForDisplay
    }

    /// 学校 · 年级（虚拟成员列表等）；任一侧为空则只展示有值的一侧。
    var profileSchoolGradeForDisplay: String? {
        let schoolTrimmed = school?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gradeTrimmed = grade?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSchool = schoolTrimmed.isEmpty == false
        let hasGrade = gradeTrimmed.isEmpty == false
        switch (hasSchool, hasGrade) {
        case (true, true):
            return "\(schoolTrimmed) · \(gradeTrimmed)"
        case (true, false):
            return schoolTrimmed
        case (false, true):
            return gradeTrimmed
        case (false, false):
            return nil
        }
    }

    /// 档案联系信息摘要（邮箱 + 主手机号），用于列表副标题。
    var profileContactSummaryForDisplay: String {
        var parts: [String] = []
        if let email = profileEmailForDisplay, email != displayName {
            parts.append(email)
        }
        if let phone = profileMainPhoneForDisplay {
            parts.append(phone)
        }
        return parts.joined(separator: " · ")
    }

    static func uniqueMembershipsFlattened(from profiles: [FamilyProfile]) -> [HouseholdMembership] {
        var seen = Set<UUID>()
        var ordered: [HouseholdMembership] = []
        for profile in profiles {
            guard let list = profile.householdMemberships else { continue }
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

    /// 保存前将空白选填字段统一为 `nil`，便于上层与 Supabase 更新 payload 一致处理「清空」。
    func normalizedForProfileUpdate() -> LocalProfileDraft {
        var copy = self
        copy.avatarURL = Self.nilIfBlank(avatarURL)
        copy.gender = Self.nilIfBlank(gender)
        copy.idCardNum = Self.nilIfBlank(idCardNum)
        copy.passportNum = Self.nilIfBlank(passportNum)
        copy.permitNum = Self.nilIfBlank(permitNum)
        copy.school = Self.nilIfBlank(school)
        copy.grade = Self.nilIfBlank(grade)
        copy.email = Self.nilIfBlank(email)
        copy.mainPhone = Self.nilIfBlank(mainPhone)
        copy.secondPhone = Self.nilIfBlank(secondPhone)
        return copy
    }

    private static func nilIfBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
