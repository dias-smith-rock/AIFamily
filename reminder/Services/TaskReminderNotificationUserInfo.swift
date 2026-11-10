import Foundation

/// 本地任务提醒 / 远程指派推送 `userInfo` 键与解析（点击通知进 App 时用于切群组与打开详情）。
enum TaskReminderNotificationUserInfo {
    static let taskId = "taskId"
    static let householdId = "householdId"
    static let householdName = "householdName"
    static let isFlexibleTodo = "isFlexibleTodo"
    /// Remote push: `"task_assigned"`. Local reminders omit this key.
    static let type = "type"
    static let taskAssignedType = "task_assigned"

    struct Tap: Sendable, Equatable {
        let taskId: UUID
        let householdId: UUID
        let householdName: String?
        let isFlexibleTodo: Bool
    }

    static func dictionary(
        taskId: UUID,
        householdId: UUID,
        householdName: String?,
        isFlexibleTodo: Bool
    ) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            Self.taskId: taskId.uuidString.lowercased(),
            Self.householdId: householdId.uuidString.lowercased(),
            Self.isFlexibleTodo: isFlexibleTodo
        ]
        if let name = householdName?.trimmingCharacters(in: .whitespacesAndNewlines), name.isEmpty == false {
            info[Self.householdName] = name
        }
        return info
    }

    static func parse(_ userInfo: [AnyHashable: Any]) -> Tap? {
        if let typeRaw = stringValue(userInfo[Self.type]),
           typeRaw.isEmpty == false,
           typeRaw != taskAssignedType {
            return nil
        }
        guard let taskRaw = stringValue(userInfo[Self.taskId]),
              let taskId = UUID(uuidString: taskRaw) else {
            return nil
        }
        guard let householdRaw = stringValue(userInfo[Self.householdId]),
              let householdId = UUID(uuidString: householdRaw) else {
            return nil
        }
        let householdName = stringValue(userInfo[Self.householdName])
        let isFlexibleTodo = boolValue(userInfo[Self.isFlexibleTodo]) ?? false
        return Tap(taskId: taskId, householdId: householdId, householdName: householdName, isFlexibleTodo: isFlexibleTodo)
    }

    private static func stringValue(_ raw: Any?) -> String? {
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = raw as? NSString {
            let trimmed = (value as String).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func boolValue(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        if let number = raw as? NSNumber { return number.boolValue }
        if let text = stringValue(raw)?.lowercased() {
            if text == "true" || text == "1" { return true }
            if text == "false" || text == "0" { return false }
        }
        return nil
    }
}

extension Notification.Name {
    /// `object` 为 `TaskReminderNotificationUserInfo.Tap`。
    static let taskReminderNotificationTapped = Notification.Name("taskReminderNotificationTapped")
}
