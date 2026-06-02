import Foundation
import UserNotifications

/// 处理本地任务提醒的点击与前台展示；路由由 `ContentView` 监听 `.taskReminderNotificationTapped` 完成。
final class TaskReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TaskReminderNotificationDelegate()

    private override init() {
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo
        guard let tap = TaskReminderNotificationUserInfo.parse(userInfo) else { return }

        NotificationCenter.default.post(
            name: .taskReminderNotificationTapped,
            object: tap
        )
    }
}
