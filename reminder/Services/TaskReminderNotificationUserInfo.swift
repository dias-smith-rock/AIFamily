import Foundation

/// 本地任务提醒通知 `userInfo` 键与解析（点击通知进 App 时用于切群组与打开详情）。
enum TaskReminderNotificationUserInfo {
    static let taskId = "taskId"
    static let householdId = "householdId"
    static let householdName = "householdName"
    static let isFlexibleTodo = "isFlexibleTodo"

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
        guard let taskRaw = userInfo[Self.taskId] as? String,
              let taskId = UUID(uuidString: taskRaw) else {
            return nil
        }
        guard let householdRaw = userInfo[Self.householdId] as? String,
              let householdId = UUID(uuidString: householdRaw) else {
            return nil
        }
        let householdName = userInfo[Self.householdName] as? String
        let isFlexibleTodo = userInfo[Self.isFlexibleTodo] as? Bool ?? false
        return Tap(taskId: taskId, householdId: householdId, householdName: householdName, isFlexibleTodo: isFlexibleTodo)
    }
}

extension Notification.Name {
    /// `object` 为 `TaskReminderNotificationUserInfo.Tap`。
    static let taskReminderNotificationTapped = Notification.Name("taskReminderNotificationTapped")
}
