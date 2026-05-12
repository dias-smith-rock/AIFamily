import SwiftUI

/// 任务编辑 / 新建 UI（`CreateTaskView`）：分组卡片、简/详展开，与日程详情 Sheet 共用。
struct EditTaskView: View {
    @EnvironmentObject private var appRouter: AppRouter

    let task: FamilyTask
    let onUpdateSuccess: (FamilyTask) -> Void
    var onAlarmSync: ((FamilyTask) -> Void)?

    init(
        task: FamilyTask,
        onUpdateSuccess: @escaping (FamilyTask) -> Void,
        onAlarmSync: ((FamilyTask) -> Void)? = nil
    ) {
        self.task = task
        self.onUpdateSuccess = onUpdateSuccess
        self.onAlarmSync = onAlarmSync
    }

    var body: some View {
        CreateTaskView(
            editingTask: task,
            onUpdateSuccess: onUpdateSuccess,
            onAlarmSync: onAlarmSync
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
