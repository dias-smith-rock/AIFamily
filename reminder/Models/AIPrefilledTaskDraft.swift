import UIKit

/// AI 识图后预填创建任务 Sheet 的草稿（含原图附件）。
struct AIPrefilledTaskDraft: Identifiable {
    let id = UUID()
    var title: String
    var description: String?
    var dueDate: Date?
    var locationName: String?
    var attachmentImage: UIImage
}
