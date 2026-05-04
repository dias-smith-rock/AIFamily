import Foundation

// MARK: - 5. 消息与反馈 (Feedback)
/// 系统下发消息时 `senderId` 为空。
struct Feedback: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    let taskId: UUID
    let senderId: UUID?
    var contentType: FeedbackContentType

    var textContent: String?
    var voiceUrl: String?
    var imageUrls: [String]?
    var videoUrl: String?
    var duration: Int?

    /// 反应表情：`["👍": [memberId1, memberId2]]`
    var reactions: [String: [UUID]]?
    var readBy: [UUID]?
    var isDeleted: Bool
    var mediaClearedAt: Date?

    let createdAt: Date
}
