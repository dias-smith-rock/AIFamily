import Foundation

// MARK: - tasks.task_type

enum TaskTypeKind: String, Codable, Equatable {
    case scheduled
    case flexible
    case expense
    case income
}

extension FamilyTask {
    /// `tasks.task_type`；`nil` / 空视为定时日程（兼容历史数据）。
    var resolvedTaskType: TaskTypeKind {
        guard let raw = taskType?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false
        else {
            return .scheduled
        }
        return TaskTypeKind(rawValue: raw) ?? .scheduled
    }

    var isFlexibleTodo: Bool {
        resolvedTaskType == .flexible
    }

    /// 灵活待办 Tab 过滤：排除账本行。
    var isFlexibleTodoCandidate: Bool {
        isFlexibleTodo && isLedgerEntry == false
    }

    /// 在日程 Tab 时间轴 / 列表中展示的任务（`scheduled`，排除系统任务与账本行）。
    var isScheduledCalendarTask: Bool {
        guard isBirthdaySystemTask == false else { return false }
        guard isLedgerEntry == false else { return false }
        return resolvedTaskType == .scheduled
    }

    /// 群组生日同步等系统任务，不进日程与待办 Tab。
    var isBirthdaySystemTask: Bool {
        taskType == "birthday_reminder"
    }

    /// 灵活待办截止日（`end_datetime` 的日历日）；无则 `nil`。
    var flexibleDeadlineDay: Date? {
        guard isFlexibleTodo, let endDatetime else { return nil }
        return Calendar.current.startOfDay(for: endDatetime)
    }

    /// 本地通知与排序用的时刻：定时用开始 `due_date`，灵活用截止 `end_datetime`。
    var alarmAnchorDate: Date? {
        if isFlexibleTodo {
            return endDatetime
        }
        return dueDate
    }
}
