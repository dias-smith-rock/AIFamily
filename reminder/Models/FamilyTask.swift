import Foundation

// MARK: - 4. 家庭任务 (FamilyTask)
/// 命名为 `FamilyTask` 是为了避免与 Swift 并发框架的 `Swift.Task` 冲突。
struct FamilyTask: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    let creatorId: UUID
    var parentTaskId: UUID?
    var originalDueDate: Date?

    var involvedMemberIds: [UUID]?
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
    var isAllDay: Bool
    var recurrenceRule: String?
    var reminderOffsets: [Int]?

    var estimatedCost: Int?

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
