import Foundation

extension FamilyTask {
    /// 是否存在重复规则（用于完成后的 UI 分支）。
    var isRecurring: Bool {
        guard let rule = recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return rule.isEmpty == false
    }

    /// 母任务：`recurrence_rule` 非空且 `parent_task_id` 为空。
    var isRecurringSeriesMother: Bool {
        guard let rule = recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        guard rule.isEmpty == false else { return false }
        return parentTaskId == nil
    }

    /// 由展开引擎生成的子任务。
    var isRecurringSeriesChild: Bool {
        parentTaskId != nil
    }

    /// 与旧版 `group_id` 批量行兼容：任一为真则编辑/删除时需询问范围。
    var needsRecurringScopeDialog: Bool {
        if parentTaskId != nil { return true }
        if isRecurringSeriesMother { return true }
        if groupId != nil { return true }
        return false
    }

    /// 用于拉取「同一条重复序列」：优先 `parent_task_id` 链，其次旧 `group_id`。
    enum SeriesGrouping: Equatable {
        case byParentRoot(UUID)
        case byLegacyGroup(UUID)
    }

    var seriesGrouping: SeriesGrouping? {
        if let parentTaskId {
            return .byParentRoot(parentTaskId)
        }
        if isRecurringSeriesMother {
            return .byParentRoot(id)
        }
        if let groupId {
            return .byLegacyGroup(groupId)
        }
        return nil
    }

    /// 列表 / 详情展示用的计划开始时刻。
    var scheduleStartDate: Date {
        dueDate ?? originalDueDate ?? createdAt
    }

    /// 计划结束时刻：优先 `end_datetime`，但不短于 `scheduleStartDate + duration_minutes`。
    var resolvedEndDate: Date? {
        let start = scheduleStartDate
        let durationEnd = Calendar.current.date(
            byAdding: .minute,
            value: max(1, durationMinutes),
            to: start
        )
        guard let endDatetime, endDatetime > start else {
            return durationEnd
        }
        if let durationEnd {
            return max(endDatetime, durationEnd)
        }
        return endDatetime
    }

    /// 时间轴「此刻」指示器与区间计算用的结束时刻（非可选，保证晚于开始时刻）。
    var timelineEndDate: Date {
        resolvedEndDate ?? Calendar.current.date(
            byAdding: .minute,
            value: max(1, durationMinutes),
            to: scheduleStartDate
        ) ?? scheduleStartDate
    }
}
