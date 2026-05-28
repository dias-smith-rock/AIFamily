import Foundation

/// `task_attachments` 表行：任务与 Storage 图片的关联。
struct TaskAttachment: Codable, Equatable, Sendable {
    var taskId: UUID
    var fileUrl: String
    var fileType: String

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case fileUrl = "file_url"
        case fileType = "file_type"
    }
}
