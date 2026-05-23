import Foundation

// MARK: - 4. 家庭任务 (FamilyTask)
/// 命名为 `FamilyTask` 是为了避免与 Swift 并发框架的 `Swift.Task` 冲突。
struct FamilyTask: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    let creatorId: UUID
    var parentTaskId: UUID?
    var groupId: UUID? = nil
    var originalDueDate: Date?

    /// 被指派的成员在 `household_memberships` 表中的 **主键 id**（与当前登录用户的 **membership id** 同维度），不是 `auth.users.id`。
    var involvedMemberIds: [UUID]?
    /// 新版单目标档案字段：`target_profile_id`。
    var targetProfileId: UUID?
    /// 旧版多目标档案字段：`target_profile_ids`。
    var targetProfileIds: [UUID]?
    var targetSubject: String?
    var title: String
    var description: String?
    var originalPrompt: String?
    var attachmentUrls: [String]?

    // JSONB 字段：直接映射为嵌套 Struct / 字典
    var externalContacts: [String: String]?
    var locationData: LocationData?
    var externalSyncRefs: [String: [String: String]]?
    var alarmSetBy: [String: AlarmConfig]?

    var status: TaskStatus
    var priority: TaskPriority
    var dueDate: Date?
    /// 对应 `tasks.end_datetime`（TIMESTAMPTZ，可空）；应不早于 `due_date`。
    var endDatetime: Date? = nil
    /// 对应 `tasks.duration_minutes`（任务时长，单位：分钟；库表 NOT NULL）。
    var durationMinutes: Int = FamilyTask.defaultDurationMinutes
    var isAllDay: Bool
    var recurrenceRule: String?
    /// `tasks.recurrence_end_date`（TIMESTAMPTZ）；无重复规则时必须为 `nil`。
    var recurrenceEndDate: Date? = nil
    /// `tasks.recurrence_interval`；无重复规则时必须为 `nil`；有重复且未单独配置 UI 时由写入层使用 `1`。
    var recurrenceInterval: Int? = nil
    var reminderOffsets: [Int]?

    var estimatedCost: Int?

    /// `tasks.background_color`，`#RRGGBB`；`nil` 表示列表使用系统默认二级背景。
    var backgroundColor: String? = nil
    /// `tasks.emergency_phone`，用于卡片快捷拨号 / FaceTime。
    var emergencyPhone: String? = nil

    let createdAt: Date
    let updatedAt: Date

    // MARK: - JSONB Nested Structs
    struct LocationData: Codable, Equatable {
        var name: String?
        var address: String?
        var latitude: Double?
        var longitude: Double?
    }

    struct AlarmConfig: Codable, Equatable {
        /// `app_push` 或 `phone_call`
        var type: String
        var phone: String?
    }

    init(
        id: UUID,
        householdId: UUID,
        creatorId: UUID,
        parentTaskId: UUID? = nil,
        groupId: UUID? = nil,
        originalDueDate: Date? = nil,
        involvedMemberIds: [UUID]? = nil,
        targetProfileId: UUID? = nil,
        targetProfileIds: [UUID]? = nil,
        targetSubject: String? = nil,
        title: String,
        description: String? = nil,
        originalPrompt: String? = nil,
        attachmentUrls: [String]? = nil,
        externalContacts: [String: String]? = nil,
        locationData: LocationData? = nil,
        externalSyncRefs: [String: [String: String]]? = nil,
        alarmSetBy: [String: AlarmConfig]? = nil,
        status: TaskStatus,
        priority: TaskPriority,
        dueDate: Date? = nil,
        endDatetime: Date? = nil,
        durationMinutes: Int = FamilyTask.defaultDurationMinutes,
        isAllDay: Bool,
        recurrenceRule: String? = nil,
        recurrenceEndDate: Date? = nil,
        recurrenceInterval: Int? = nil,
        reminderOffsets: [Int]? = nil,
        estimatedCost: Int? = nil,
        backgroundColor: String? = nil,
        emergencyPhone: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.householdId = householdId
        self.creatorId = creatorId
        self.parentTaskId = parentTaskId
        self.groupId = groupId
        self.originalDueDate = originalDueDate
        self.involvedMemberIds = involvedMemberIds
        self.targetProfileId = targetProfileId
        self.targetProfileIds = targetProfileIds
        self.targetSubject = targetSubject
        self.title = title
        self.description = description
        self.originalPrompt = originalPrompt
        self.attachmentUrls = attachmentUrls
        self.externalContacts = externalContacts
        self.locationData = locationData
        self.externalSyncRefs = externalSyncRefs
        self.alarmSetBy = alarmSetBy
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.endDatetime = endDatetime
        self.durationMinutes = durationMinutes
        self.isAllDay = isAllDay
        self.recurrenceRule = recurrenceRule
        self.recurrenceEndDate = recurrenceEndDate
        self.recurrenceInterval = recurrenceInterval
        self.reminderOffsets = reminderOffsets
        self.estimatedCost = estimatedCost
        self.backgroundColor = backgroundColor
        self.emergencyPhone = emergencyPhone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case householdId
        case creatorId
        case parentTaskId
        case groupId
        case originalDueDate
        case involvedMemberIds
        case targetProfileId
        case targetProfileIds
        case targetSubject
        case title
        case description
        case originalPrompt
        case attachmentUrls
        case externalContacts
        case locationData
        case externalSyncRefs
        case alarmSetBy
        case status
        case priority
        case dueDate
        case endDatetime
        case durationMinutes
        case isAllDay
        case recurrenceRule
        case recurrenceEndDate
        case recurrenceInterval
        case reminderOffsets
        case estimatedCost
        case backgroundColor
        case emergencyPhone
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        creatorId = try container.decode(UUID.self, forKey: .creatorId)
        parentTaskId = try container.decodeIfPresent(UUID.self, forKey: .parentTaskId)
        groupId = try container.decodeIfPresent(UUID.self, forKey: .groupId)
        originalDueDate = try container.decodeIfPresent(Date.self, forKey: .originalDueDate)
        involvedMemberIds = try container.decodeIfPresent([UUID].self, forKey: .involvedMemberIds)
        targetProfileId = try container.decodeIfPresent(UUID.self, forKey: .targetProfileId)
        targetProfileIds = try container.decodeIfPresent([UUID].self, forKey: .targetProfileIds)
        targetSubject = try container.decodeIfPresent(String.self, forKey: .targetSubject)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        originalPrompt = try container.decodeIfPresent(String.self, forKey: .originalPrompt)
        attachmentUrls = try container.decodeIfPresent([String].self, forKey: .attachmentUrls)
        externalContacts = try container.decodeIfPresent([String: String].self, forKey: .externalContacts)
        locationData = try container.decodeIfPresent(LocationData.self, forKey: .locationData)
        externalSyncRefs = try container.decodeIfPresent(
            [String: [String: String]].self,
            forKey: .externalSyncRefs
        )
        alarmSetBy = try container.decodeIfPresent([String: AlarmConfig].self, forKey: .alarmSetBy)
        status = try container.decode(TaskStatus.self, forKey: .status)
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        endDatetime = try container.decodeIfPresent(Date.self, forKey: .endDatetime)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
            ?? Self.legacyCacheFallbackDurationMinutes
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        recurrenceRule = try container.decodeIfPresent(String.self, forKey: .recurrenceRule)
        recurrenceEndDate = try container.decodeIfPresent(Date.self, forKey: .recurrenceEndDate)
        recurrenceInterval = try container.decodeIfPresent(Int.self, forKey: .recurrenceInterval)
        reminderOffsets = try container.decodeIfPresent([Int].self, forKey: .reminderOffsets)
        estimatedCost = try container.decodeIfPresent(Int.self, forKey: .estimatedCost)
        backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
        emergencyPhone = try container.decodeIfPresent(String.self, forKey: .emergencyPhone)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(creatorId, forKey: .creatorId)
        try container.encodeIfPresent(parentTaskId, forKey: .parentTaskId)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        try container.encodeIfPresent(originalDueDate, forKey: .originalDueDate)
        try container.encodeIfPresent(involvedMemberIds, forKey: .involvedMemberIds)
        try container.encodeIfPresent(targetProfileId, forKey: .targetProfileId)
        try container.encodeIfPresent(targetProfileIds, forKey: .targetProfileIds)
        try container.encodeIfPresent(targetSubject, forKey: .targetSubject)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(originalPrompt, forKey: .originalPrompt)
        try container.encodeIfPresent(attachmentUrls, forKey: .attachmentUrls)
        try container.encodeIfPresent(externalContacts, forKey: .externalContacts)
        try container.encodeIfPresent(locationData, forKey: .locationData)
        try container.encodeIfPresent(externalSyncRefs, forKey: .externalSyncRefs)
        try container.encodeIfPresent(alarmSetBy, forKey: .alarmSetBy)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(endDatetime, forKey: .endDatetime)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(isAllDay, forKey: .isAllDay)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        try container.encodeIfPresent(recurrenceEndDate, forKey: .recurrenceEndDate)
        try container.encodeIfPresent(recurrenceInterval, forKey: .recurrenceInterval)
        try container.encodeIfPresent(reminderOffsets, forKey: .reminderOffsets)
        try container.encodeIfPresent(estimatedCost, forKey: .estimatedCost)
        try container.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try container.encodeIfPresent(emergencyPhone, forKey: .emergencyPhone)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

extension FamilyTask {
    /// 与数据库 `duration_minutes` 列默认值及时间轴 fallback 对齐。
    static let defaultDurationMinutes = 60
    /// 本地旧缓存缺少 `duration_minutes` 时的解码兜底（向下兼容）。
    static let legacyCacheFallbackDurationMinutes = 30

    /// `involved_member_ids` 为数据库 `NULL`（或空数组）时，表示任务指派给**整个家庭**，
    /// 语义随成员增减扩展；若写入具体 UUID 列表则为创建时的指派快照（列表元素为 **membership id**）。
    var involvesWholeHousehold: Bool {
        guard let ids = involvedMemberIds else { return true }
        return ids.isEmpty
    }

    /// 当前 **成员身份**（`household_memberships.id`）是否在本任务的指派范围内。
    func involvesMembership(id membershipId: UUID) -> Bool {
        involvesWholeHousehold || (involvedMemberIds?.contains(membershipId) == true)
    }
}
