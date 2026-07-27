import Foundation

extension Notification.Name {
    /// 游客实质操作后调度绑定引导；主 Tab 已显示时用此通知立即弹出。
    static let anonymousBindPromptDidSchedule = Notification.Name("anonymousBindPromptDidSchedule")
}

/// 游客创建任务 / Todo / 记账 / 成员后展示绑定账号引导（建群/加群/纯进入不触发）。
enum AnonymousBindPromptStore {
    private static let pendingKey = "anonymous_bind_prompt_pending"

    static func schedule() {
        UserDefaults.standard.set(true, forKey: pendingKey)
        NotificationCenter.default.post(name: .anonymousBindPromptDidSchedule, object: nil)
    }

    static func clearPending() {
        UserDefaults.standard.set(false, forKey: pendingKey)
    }

    /// 一次性清掉「建群即 schedule」遗留的 pending，避免无实质操作仍弹引导。
    static func clearStaleGroupActionPendingIfNeeded() {
        let migrationKey = "anonymous_bind_prompt_cleared_group_pending_v1"
        guard UserDefaults.standard.bool(forKey: migrationKey) == false else { return }
        clearPending()
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    static func consumeIfPending() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return false }
        UserDefaults.standard.set(false, forKey: pendingKey)
        return true
    }
}
