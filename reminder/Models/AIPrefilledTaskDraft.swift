import UIKit

/// AI 识图后预填创建任务 Sheet 的草稿（含原图附件）。
struct AIPrefilledTaskDraft: Identifiable {
    let id = UUID()
    var title: String
    var description: String?
    var dueDate: Date?
    var endDatetime: Date?
    var isAllDay: Bool
    var durationMinutes: Int?
    var costDisplay: String?
    var locationName: String?
    var assigneeMembershipIds: Set<UUID>
    var targetProfileIds: Set<UUID>
    var isPriorityUrgent: Bool
    var prefersFlexibleTask: Bool
    /// 原图（压缩后）预览。
    var attachmentImage: UIImage
    /// 与上传 Supabase 相同的 JPEG 字节，保存任务时原样上传为附件。
    var attachmentJPEGData: Data
}
