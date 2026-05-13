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
}

extension FamilyTask {
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
