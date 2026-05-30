import Foundation

/// 任务表单模式：决定新建/编辑 UI 与写入 `tasks.task_type` 的分流。
@MainActor
enum EditTaskViewModel {
    enum TaskMode: Equatable {
        case scheduled
        case flexible
    }

    static func mode(forEditing task: FamilyTask) -> TaskMode {
        task.isFlexibleTodo ? .flexible : .scheduled
    }

    static func taskType(for mode: TaskMode) -> String {
        switch mode {
        case .scheduled:
            return TaskTypeKind.scheduled.rawValue
        case .flexible:
            return TaskTypeKind.flexible.rawValue
        }
    }

    static func isFlexibleDeadline(for mode: TaskMode) -> Bool {
        mode == .flexible
    }

    /// 灵活待办默认截止：当日 23:59。
    static func defaultFlexibleDeadlineDate(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: dayStart) ?? dayStart
    }

    /// 持久化前归一化：所选自然日的 23:59。
    static func normalizedFlexibleEndDatetime(from pickerDate: Date) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: pickerDate)
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: dayStart) ?? dayStart
    }
}
