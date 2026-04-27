import Foundation

struct Task: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var note: String?
    var scheduledAt: Date
    var dueAt: Date?
    var location: String?
    var assigneeId: UUID
    var childName: String?
    var status: TaskStatus
    var priority: TaskPriority
    var source: TaskSource
    var createdAt: Date
    var updatedAt: Date

    enum TaskStatus: String, Codable {
        case pending
        case inProgress = "in_progress"
        case completed
        case overdue
    }

    enum TaskPriority: String, Codable {
        case low
        case normal
        case high
        case urgent
    }

    enum TaskSource: String, Codable {
        case manual
        case aiAssistant = "ai_assistant"
        case importedMessage = "imported_message"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case note
        case scheduledAt = "scheduled_at"
        case dueAt = "due_at"
        case location
        case assigneeId = "assignee_id"
        case childName = "child_name"
        case status
        case priority
        case source
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
