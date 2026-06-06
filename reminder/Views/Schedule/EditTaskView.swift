import SwiftUI
import UIKit

/// 任务新建 / 编辑统一入口：由 `TaskMode` 决定定时日程或灵活待办 UI。
struct EditTaskView: View {
    @EnvironmentObject private var appRouter: AppRouter

    private let editingTask: FamilyTask?
    private let formMode: EditTaskViewModel.TaskMode
    private let familyProfiles: [FamilyProfile]
    private let initialTitle: String?
    private let initialNote: String?
    private let initialLocationName: String?
    private let initialDueDate: Date?
    private let initialAttachmentImages: [UIImage]
    private let initialAttachmentJPEGData: [Data]
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
        self.initialNote = nil
        self.initialLocationName = nil
        self.initialDueDate = nil
        self.initialAttachmentImages = []
        self.initialAttachmentJPEGData = []
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
        initialNote: String? = nil,
        initialLocationName: String? = nil,
        initialDueDate: Date? = nil,
        initialAttachmentImages: [UIImage] = [],
        initialAttachmentJPEGData: [Data] = [],
        defaultDueDate: Date? = nil,
        defaultAllDayForNewTask: Bool = false,
        onSaveSuccess: ((Date) -> Void)? = nil,
        onAlarmSync: ((FamilyTask) -> Void)? = nil
    ) {
        self.editingTask = nil
        self.formMode = formMode
        self.familyProfiles = familyProfiles
        self.initialTitle = initialTitle
        self.initialNote = initialNote
        self.initialLocationName = initialLocationName
        self.initialDueDate = initialDueDate
        self.initialAttachmentImages = initialAttachmentImages
        self.initialAttachmentJPEGData = initialAttachmentJPEGData
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
            initialNote: initialNote,
            initialLocationName: initialLocationName,
            initialDueDate: initialDueDate,
            initialAttachmentImages: initialAttachmentImages,
            initialAttachmentJPEGData: initialAttachmentJPEGData,
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
