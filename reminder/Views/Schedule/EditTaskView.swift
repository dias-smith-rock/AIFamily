import SwiftUI

/// 任务编辑 / 新建 UI（`CreateTaskView`）：分组卡片、简/详展开，与日程详情 Sheet 共用。
/// 性能：`CreateTaskView` 内已对标题输入与「时间/重复」区块解耦，并重负载异步处理；编辑入口仅转发。
struct EditTaskView: View {
    @EnvironmentObject private var appRouter: AppRouter

    let task: FamilyTask
    let familyProfiles: [FamilyProfile]
    let onUpdateSuccess: (FamilyTask) -> Void
    var onAlarmSync: ((FamilyTask) -> Void)?

    init(
        task: FamilyTask,
        familyProfiles: [FamilyProfile] = [],
        onUpdateSuccess: @escaping (FamilyTask) -> Void,
        onAlarmSync: ((FamilyTask) -> Void)? = nil
    ) {
        self.task = task
        self.familyProfiles = familyProfiles
        self.onUpdateSuccess = onUpdateSuccess
        self.onAlarmSync = onAlarmSync
    }

    var body: some View {
        CreateTaskView(
            editingTask: task,
            familyProfiles: familyProfiles,
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
