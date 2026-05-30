import Foundation

/// 本地闹钟同步专用轻量 DTO，在任意 `await` 之前由 `FamilyTask` 拆出基础类型再传入异步层，
/// 避免大体量模型作为 `async` 参数在挂起恢复后出现异常。
struct TaskAlarmPayload: Sendable {
    let id: UUID
    let title: String
    let groupName: String?
    let priority: TaskPriority
    let status: TaskStatus
    let isAllDay: Bool
    let dueDate: Date?
    /// 与 `FamilyTask.reminderOffsets` 一致：每条为「截止前提前分钟数」；`nil` 或空表示不设提前量。
    let reminderOffsets: [Int]?
}

extension TaskAlarmPayload {
    /// 在同步阶段（首个 `await` 之前）从完整任务模型抽取字段。
    init(schedulingFrom task: FamilyTask, profiles: [FamilyProfile] = [], locale: Locale) {
        self.init(
            id: task.id,
            title: BirthdayTaskDisplay.resolvedTitle(for: task, profiles: profiles, locale: locale),
            groupName: BirthdayTaskDisplay.resolvedTargetDisplayName(for: task, profiles: profiles),
            priority: task.priority,
            status: task.status,
            isAllDay: task.isAllDay,
            dueDate: task.dueDate,
            reminderOffsets: task.reminderOffsets
        )
    }

    /// 在进入 `async` 闹钟逻辑时再拷一层，避免异步帧内对入参结构体的重复读取与长字符串插值触发异常。
    func detachedCopy() -> TaskAlarmPayload {
        let offsetsCopy = reminderOffsets.map { Array($0) }
        return TaskAlarmPayload(
            id: id,
            title: String(title),
            groupName: groupName.map { String($0) },
            priority: priority,
            status: status,
            isAllDay: isAllDay,
            dueDate: dueDate,
            reminderOffsets: offsetsCopy
        )
    }
}
