import SwiftUI

/// 任务新建 / 编辑统一入口：由 `TaskMode` 决定定时日程或灵活待办 UI。
struct EditTaskView: View {
    @EnvironmentObject private var appRouter: AppRouter

    private let editingTask: FamilyTask?
    private let formMode: EditTaskViewModel.TaskMode
    private let familyProfiles: [FamilyProfile]
    private let initialTitle: String?
    private let defaultDueDate: Date?
    private let defaultAllDayForNewTask: Bool
    private let onSaveSuccess: ((Date) -> Void)?
    private let onUpdateSuccess: ((FamilyTask) -> Void)?
    private let onAlarmSync: ((FamilyTask) -> Void)?

    /// 编辑已有任务（模式由任务 `task_type` 推断）。
    init(
        task: FamilyTask,
        familyProfiles: [FamilyProfile] = [],
        onUpdateSuccess: @escaping (FamilyTask) -> Void,
        onAlarmSync: ((FamilyTask) -> Void)? = nil
    ) {
        self.editingTask = task
        self.formMode = EditTaskViewModel.mode(forEditing: task)
        self.familyProfiles = familyProfiles
        self.initialTitle = nil
        self.defaultDueDate = nil
        self.defaultAllDayForNewTask = false
        self.onSaveSuccess = nil
        self.onUpdateSuccess = onUpdateSuccess
        self.onAlarmSync = onAlarmSync
    }

    /// 新建任务（由入口指定 `.scheduled` 或 `.flexible`）。
    init(
        formMode: EditTaskViewModel.TaskMode,
        familyProfiles: [FamilyProfile] = [],
        initialTitle: String? = nil,
        defaultDueDate: Date? = nil,
        defaultAllDayForNewTask: Bool = false,
        onSaveSuccess: ((Date) -> Void)? = nil,
        onAlarmSync: ((FamilyTask) -> Void)? = nil
    ) {
        self.editingTask = nil
        self.formMode = formMode
        self.familyProfiles = familyProfiles
        self.initialTitle = initialTitle
        self.defaultDueDate = defaultDueDate
        self.defaultAllDayForNewTask = defaultAllDayForNewTask
        self.onSaveSuccess = onSaveSuccess
        self.onUpdateSuccess = nil
        self.onAlarmSync = onAlarmSync
    }

    var body: some View {
        CreateTaskView(
            editingTask: editingTask,
            formMode: formMode,
            familyProfiles: familyProfiles,
            initialTitle: initialTitle,
            defaultDueDate: defaultDueDate,
            defaultAllDayForNewTask: defaultAllDayForNewTask,
            onSaveSuccess: onSaveSuccess,
            onUpdateSuccess: onUpdateSuccess,
            onAlarmSync: onAlarmSync
        )
        .environmentObject(appRouter)
    }
}

#Preview("新建日程") {
    EditTaskView(formMode: .scheduled)
        .environmentObject(AppRouter())
}

#Preview("编辑") {
    EditTaskView(
        task: FamilyTask.mockTasks[1],
        onUpdateSuccess: { _ in }
    )
    .environmentObject(AppRouter())
}
