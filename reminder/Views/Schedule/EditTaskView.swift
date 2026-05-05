import SwiftUI

/// 任务编辑表单：复用 `CreateTaskView` 的编辑模式，供详情页以 Sheet 呈现。
struct EditTaskView: View {
    @EnvironmentObject private var appRouter: AppRouter

    let task: FamilyTask
    let onUpdateSuccess: (FamilyTask) -> Void

    var body: some View {
        CreateTaskView(
            editingTask: task,
            onUpdateSuccess: onUpdateSuccess
        )
        .environmentObject(appRouter)
    }
}

#Preview {
    EditTaskView(
        task: FamilyTask.mockTasks[1],
        onUpdateSuccess: { _ in }
    )
    .environmentObject(AppRouter())
}
