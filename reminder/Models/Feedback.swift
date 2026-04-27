import Foundation

struct Feedback: Identifiable, Codable, Equatable {
    let id: UUID
    var taskId: UUID
    var senderId: UUID
    var type: FeedbackType
    var text: String?
    var audioURL: URL?
    var audioDurationSeconds: Int?
    var isRead: Bool
    var createdAt: Date

    enum FeedbackType: String, Codable {
        case text
        case voice
        case system
    }

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case senderId = "sender_id"
        case type
        case text
        case audioURL = "audio_url"
        case audioDurationSeconds = "audio_duration_seconds"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}
