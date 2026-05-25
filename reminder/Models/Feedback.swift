import Foundation

// MARK: - 5. 消息与反馈 (Feedback)
/// 系统下发消息时 `senderId` 为空。
struct Feedback: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID?
    let taskId: UUID
    let senderId: UUID?
    let content: String?
    let voiceUrl: String?
    let imageUrls: [String]?
    let readBy: [UUID]?
    let isDeleted: Bool?
    let replyToId: UUID?
    let createdAt: Date
    let updatedAt: Date?
    let mediaClearedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case taskId = "task_id"
        case senderId = "sender_id"
        case content
        case voiceUrl = "voice_url"
        case imageUrls = "image_urls"
        case readBy = "read_by"
        case isDeleted = "is_deleted"
        case replyToId = "reply_to_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mediaClearedAt = "media_cleared_at"
    }
}

extension Feedback {
    var isSystemMessage: Bool {
        senderId == nil
    }

    var hasVoiceAttachment: Bool {
        guard let voiceUrl else { return false }
        return voiceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var showsEditedBadge: Bool {
        updatedAt != nil
    }

    func absoluteVoiceURL() -> URL? {
        SupabasePublicStorageURL.resolve(
            storedValue: voiceUrl,
            bucket: SupabaseStorageBuckets.voiceFeedbacks
        )
    }

    func absoluteImageURLs() -> [URL] {
        (imageUrls ?? []).compactMap { path in
            SupabasePublicStorageURL.resolve(
                storedValue: path,
                bucket: SupabaseStorageBuckets.voiceFeedbacks
            )
        }
    }

    func markingRead(by readerId: UUID) -> Feedback {
        var readers = readBy ?? []
        if readers.contains(readerId) == false {
            readers.append(readerId)
        }
        return Feedback(
            id: id,
            householdId: householdId,
            taskId: taskId,
            senderId: senderId,
            content: content,
            voiceUrl: voiceUrl,
            imageUrls: imageUrls,
            readBy: readers,
            isDeleted: isDeleted,
            replyToId: replyToId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            mediaClearedAt: mediaClearedAt
        )
    }
}
