import Foundation

// MARK: - 4. 群组任务 (FamilyTask)
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
    /// 旧版「为了谁」文本快照（已废弃写入）。有关联 `target_profile_ids` 时展示层应解析当前 nickname，勿再持久化称呼。
    var targetSubject: String?
    var title: String
    var description: String?
    var originalPrompt: String?
    var attachmentUrls: [String]?

    // JSONB 字段：直接映射为嵌套 Struct / 字典
    var externalContacts: [String: String]?
    var locationData: LocationData?
    var geofence: TaskGeofence?
    var completionLocation: TaskCompletionLocation?
    var externalSyncRefs: [String: [String: String]]?
    var alarmSetBy: [String: AlarmConfig]?

    var status: TaskStatus
    var priority: TaskPriority
    /// `tasks.source`：创建来源；缺省历史数据解码为 `.manual`。
    var source: TaskSource
    /// `tasks.task_type`：`scheduled` 定时日程；`flexible` 灵活待办。
    var taskType: String? = nil
    var dueDate: Date?
    /// 对应 `tasks.end_datetime`（TIMESTAMPTZ，可空）；应不早于 `due_date`。
    var endDatetime: Date? = nil
    /// 对应 `tasks.duration_minutes`（任务时长，单位：分钟；库表 NOT NULL）。
    var durationMinutes: Int = FamilyTask.defaultDurationMinutes
    var isAllDay: Bool
    var recurrenceRule: String?
    /// `tasks.recurrence_end_date`（TIMESTAMPTZ）；无重复规则时必须为 `nil`。
    var recurrenceEndDate: Date? = nil
    /// `tasks.issue`：状态为「遇到问题」时的补充说明（与 `TaskStatus.issue` 枚举不同列）。
    var issue: String? = nil
    /// `tasks.recurrence_interval`；无重复规则时必须为 `nil`；有重复且未单独配置 UI 时由写入层使用 `1`。
    var recurrenceInterval: Int? = nil
    var reminderOffsets: [Int]?

    var estimatedCost: Int?

    /// `tasks.list_id` — 购物清单等外键（账本预留）。
    var listId: UUID? = nil
    /// `tasks.actual_amount` — 公账实付/实收金额（NUMERIC）。
    var actualAmount: Double? = nil
    /// `tasks.payer_id` — 垫付人 **membership id**。
    var payerId: UUID? = nil
    /// `tasks.split_member_ids` — 均摊成员 **membership id** 数组。
    var splitMemberIds: [UUID]? = nil
    /// `tasks.expense_category` — 分类快照，如「🍔 餐饮美食」。
    var expenseCategory: String? = nil
    /// `tasks.reward_points` — 任务可获积分（审批流预留）。
    var rewardPoints: Int? = nil
    /// `tasks.point_approved_by` — 审批家长 **membership id**。
    var pointApprovedBy: UUID? = nil

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
        geofence: TaskGeofence? = nil,
        completionLocation: TaskCompletionLocation? = nil,
        externalSyncRefs: [String: [String: String]]? = nil,
        alarmSetBy: [String: AlarmConfig]? = nil,
        status: TaskStatus,
        priority: TaskPriority,
        source: TaskSource = .manual,
        taskType: String? = nil,
        dueDate: Date? = nil,
        endDatetime: Date? = nil,
        durationMinutes: Int = FamilyTask.defaultDurationMinutes,
        isAllDay: Bool,
        recurrenceRule: String? = nil,
        recurrenceEndDate: Date? = nil,
        issue: String? = nil,
        recurrenceInterval: Int? = nil,
        reminderOffsets: [Int]? = nil,
        estimatedCost: Int? = nil,
        listId: UUID? = nil,
        actualAmount: Double? = nil,
        payerId: UUID? = nil,
        splitMemberIds: [UUID]? = nil,
        expenseCategory: String? = nil,
        rewardPoints: Int? = nil,
        pointApprovedBy: UUID? = nil,
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
        self.geofence = geofence
        self.completionLocation = completionLocation
        self.externalSyncRefs = externalSyncRefs
        self.alarmSetBy = alarmSetBy
        self.status = status
        self.priority = priority
        self.source = source
        self.taskType = taskType
        self.dueDate = dueDate
        self.endDatetime = endDatetime
        self.durationMinutes = durationMinutes
        self.isAllDay = isAllDay
        self.recurrenceRule = recurrenceRule
        self.recurrenceEndDate = recurrenceEndDate
        self.issue = issue
        self.recurrenceInterval = recurrenceInterval
        self.reminderOffsets = reminderOffsets
        self.estimatedCost = estimatedCost
        self.listId = listId
        self.actualAmount = actualAmount
        self.payerId = payerId
        self.splitMemberIds = splitMemberIds
        self.expenseCategory = expenseCategory
        self.rewardPoints = rewardPoints
        self.pointApprovedBy = pointApprovedBy
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
        case geofence
        case completionLocation
        case externalSyncRefs
        case alarmSetBy
        case status
        case priority
        case source
        case taskType
        case dueDate
        case endDatetime
        case durationMinutes
        case isAllDay
        case recurrenceRule
        case recurrenceEndDate = "recurrence_end_date"
        case legacyRecurrenceEndAt = "recurrence_end_at"
        case issue
        case recurrenceInterval
        case reminderOffsets
        case estimatedCost
        case listId
        case actualAmount
        case payerId
        case splitMemberIds
        case expenseCategory
        case rewardPoints
        case pointApprovedBy
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
        geofence = Self.decodeLenientJSON(TaskGeofence.self, from: container, forKey: .geofence)
        completionLocation = Self.decodeLenientJSON(
            TaskCompletionLocation.self,
            from: container,
            forKey: .completionLocation
        )
        externalSyncRefs = try container.decodeIfPresent(
            [String: [String: String]].self,
            forKey: .externalSyncRefs
        )
        alarmSetBy = try container.decodeIfPresent([String: AlarmConfig].self, forKey: .alarmSetBy)
        status = try container.decode(TaskStatus.self, forKey: .status)
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        source = (try? container.decode(TaskSource.self, forKey: .source)) ?? .manual
        taskType = try container.decodeIfPresent(String.self, forKey: .taskType)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        endDatetime = try container.decodeIfPresent(Date.self, forKey: .endDatetime)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
            ?? Self.legacyCacheFallbackDurationMinutes
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        recurrenceRule = try container.decodeIfPresent(String.self, forKey: .recurrenceRule)
        if let recurrenceEnd = try container.decodeIfPresent(Date.self, forKey: .recurrenceEndDate) {
            recurrenceEndDate = recurrenceEnd
        } else {
            recurrenceEndDate = try container.decodeIfPresent(Date.self, forKey: .legacyRecurrenceEndAt)
        }
        issue = try container.decodeIfPresent(String.self, forKey: .issue)
        recurrenceInterval = try container.decodeIfPresent(Int.self, forKey: .recurrenceInterval)
        reminderOffsets = try container.decodeIfPresent([Int].self, forKey: .reminderOffsets)
        estimatedCost = try container.decodeIfPresent(Int.self, forKey: .estimatedCost)
        listId = try container.decodeIfPresent(UUID.self, forKey: .listId)
        actualAmount = Self.decodeFlexibleDouble(from: container, forKey: .actualAmount)
        payerId = try container.decodeIfPresent(UUID.self, forKey: .payerId)
        splitMemberIds = try container.decodeIfPresent([UUID].self, forKey: .splitMemberIds)
        expenseCategory = try container.decodeIfPresent(String.self, forKey: .expenseCategory)
        rewardPoints = try container.decodeIfPresent(Int.self, forKey: .rewardPoints)
        pointApprovedBy = try container.decodeIfPresent(UUID.self, forKey: .pointApprovedBy)
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
        try container.encodeIfPresent(geofence, forKey: .geofence)
        try container.encodeIfPresent(completionLocation, forKey: .completionLocation)
        try container.encodeIfPresent(externalSyncRefs, forKey: .externalSyncRefs)
        try container.encodeIfPresent(alarmSetBy, forKey: .alarmSetBy)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(taskType, forKey: .taskType)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(endDatetime, forKey: .endDatetime)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(isAllDay, forKey: .isAllDay)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        try container.encodeIfPresent(recurrenceEndDate, forKey: .recurrenceEndDate)
        try container.encodeIfPresent(issue, forKey: .issue)
        try container.encodeIfPresent(recurrenceInterval, forKey: .recurrenceInterval)
        try container.encodeIfPresent(reminderOffsets, forKey: .reminderOffsets)
        try container.encodeIfPresent(estimatedCost, forKey: .estimatedCost)
        try container.encodeIfPresent(listId, forKey: .listId)
        try container.encodeIfPresent(actualAmount, forKey: .actualAmount)
        try container.encodeIfPresent(payerId, forKey: .payerId)
        try container.encodeIfPresent(splitMemberIds, forKey: .splitMemberIds)
        try container.encodeIfPresent(expenseCategory, forKey: .expenseCategory)
        try container.encodeIfPresent(rewardPoints, forKey: .rewardPoints)
        try container.encodeIfPresent(pointApprovedBy, forKey: .pointApprovedBy)
        try container.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try container.encodeIfPresent(emergencyPhone, forKey: .emergencyPhone)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

extension FamilyTask {
    /// JSONB 字段不完整时不拖垮整行任务解码（合并定位字段后常见残缺 `geofence`）。
    private static func decodeFlexibleDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key),
           let parsed = Double(stringValue.replacingOccurrences(of: ",", with: "")) {
            return parsed
        }
        return nil
    }

    private static func decodeLenientJSON<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> T? {
        guard container.contains(key) else { return nil }
        if (try? container.decodeNil(forKey: key)) == true { return nil }
        do {
            return try container.decode(T.self, forKey: key)
        } catch {
            return nil
        }
    }

    /// 与数据库 `duration_minutes` 列默认值及时间轴 fallback 对齐。
    static let defaultDurationMinutes = 60
    /// 本地旧缓存缺少 `duration_minutes` 时的解码兜底（向下兼容）。
    static let legacyCacheFallbackDurationMinutes = 30

    /// `involved_member_ids` 为数据库 `NULL`（或空数组）时，表示任务指派给**整个群组**，
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
