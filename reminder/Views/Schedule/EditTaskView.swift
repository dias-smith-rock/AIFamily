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
    private let initialEndDatetime: Date?
    private let initialIsAllDay: Bool?
    private let initialDurationMinutes: Int?
    private let initialCostDisplay: String?
    private let initialAssigneeMembershipIds: Set<UUID>?
    private let initialTargetProfileIds: Set<UUID>?
    private let initialPriorityUrgent: Bool?
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
        self.initialEndDatetime = nil
        self.initialIsAllDay = nil
        self.initialDurationMinutes = nil
        self.initialCostDisplay = nil
        self.initialAssigneeMembershipIds = nil
        self.initialTargetProfileIds = nil
        self.initialPriorityUrgent = nil
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
        initialEndDatetime: Date? = nil,
        initialIsAllDay: Bool? = nil,
        initialDurationMinutes: Int? = nil,
        initialCostDisplay: String? = nil,
        initialAssigneeMembershipIds: Set<UUID>? = nil,
        initialTargetProfileIds: Set<UUID>? = nil,
        initialPriorityUrgent: Bool? = nil,
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
        self.initialEndDatetime = initialEndDatetime
        self.initialIsAllDay = initialIsAllDay
        self.initialDurationMinutes = initialDurationMinutes
        self.initialCostDisplay = initialCostDisplay
        self.initialAssigneeMembershipIds = initialAssigneeMembershipIds
        self.initialTargetProfileIds = initialTargetProfileIds
        self.initialPriorityUrgent = initialPriorityUrgent
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
            initialEndDatetime: initialEndDatetime,
            initialIsAllDay: initialIsAllDay,
            initialDurationMinutes: initialDurationMinutes,
            initialCostDisplay: initialCostDisplay,
            initialAssigneeMembershipIds: initialAssigneeMembershipIds,
            initialTargetProfileIds: initialTargetProfileIds,
            initialPriorityUrgent: initialPriorityUrgent,
            initialAttachmentImages: initialAttachmentImages,
            initialAttachmentJPEGData: initialAttachmentJPEGData,
            defaultDueDate: defaultDueDate,
            defaultAllDayForNewTask: defaultAllDayForNewTask,
            onSaveSuccess: onSaveSuccess,
            onUpdateSuccess: onUpdateSuccess,
            onAlarmSync: onAlarmSync
        )
        .environmentObject(appRouter)
        .interactiveDismissDisabled()
        .presentationDragIndicator(.hidden)
    }
}

#Preview("New Event") {
    EditTaskView(formMode: .scheduled)
        .environmentObject(AppRouter())
        .environmentObject(AppBootstrap())
}

#Preview("Edit") {
    EditTaskView(
        task: FamilyTask.mockTasks[1],
        onUpdateSuccess: { _ in }
    )
    .environmentObject(AppRouter())
}
