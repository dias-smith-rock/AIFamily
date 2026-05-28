import Combine
import Foundation

@MainActor
final class TaskDetailViewModel: ObservableObject {
    @Published private(set) var attachments: [TaskAttachment] = []

    func loadAttachments(taskId: UUID) async {
        do {
            attachments = try await TaskAttachmentSupabaseSupport.fetchRecords(taskId: taskId)
            #if DEBUG
            print("[TaskDetailViewModel] loaded \(attachments.count) attachment(s) for task \(taskId.uuidString)")
            #endif
        } catch {
            attachments = []
            #if DEBUG
            print("[TaskDetailViewModel] load attachments failed taskId=\(taskId.uuidString) error=\(error)")
            #endif
        }
    }
}
