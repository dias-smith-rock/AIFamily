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

    init(
        id: UUID,
        title: String,
        note: String?,
        scheduledAt: Date,
        dueAt: Date?,
        location: String?,
        assigneeId: UUID,
        childName: String?,
        status: TaskStatus,
        priority: TaskPriority,
        source: TaskSource,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.scheduledAt = scheduledAt
        self.dueAt = dueAt
        self.location = location
        self.assigneeId = assigneeId
        self.childName = childName
        self.status = status
        self.priority = priority
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

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
        case scheduledAtSnake = "scheduled_at"
        case scheduledAtCamel = "scheduledAt"
        case dueAtSnake = "due_at"
        case dueAtCamel = "dueAt"
        case location
        case assigneeIdSnake = "assignee_id"
        case assigneeIdCamel = "assigneeId"
        case childNameSnake = "child_name"
        case childNameCamel = "childName"
        case status
        case priority
        case source
        case createdAtSnake = "created_at"
        case createdAtCamel = "createdAt"
        case updatedAtSnake = "updated_at"
        case updatedAtCamel = "updatedAt"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAtSnake)
            ?? container.decode(Date.self, forKey: .scheduledAtCamel)
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAtSnake)
            ?? container.decodeIfPresent(Date.self, forKey: .dueAtCamel)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        assigneeId = try container.decodeIfPresent(UUID.self, forKey: .assigneeIdSnake)
            ?? container.decode(UUID.self, forKey: .assigneeIdCamel)
        childName = try container.decodeIfPresent(String.self, forKey: .childNameSnake)
            ?? container.decodeIfPresent(String.self, forKey: .childNameCamel)
        status = try container.decode(TaskStatus.self, forKey: .status)
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        source = try container.decode(TaskSource.self, forKey: .source)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAtSnake)
            ?? container.decode(Date.self, forKey: .createdAtCamel)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAtSnake)
            ?? container.decode(Date.self, forKey: .updatedAtCamel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(scheduledAt, forKey: .scheduledAtSnake)
        try container.encodeIfPresent(dueAt, forKey: .dueAtSnake)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(assigneeId, forKey: .assigneeIdSnake)
        try container.encodeIfPresent(childName, forKey: .childNameSnake)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(source, forKey: .source)
        try container.encode(createdAt, forKey: .createdAtSnake)
        try container.encode(updatedAt, forKey: .updatedAtSnake)
    }
}
