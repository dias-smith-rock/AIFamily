import Foundation

/// 游客创建/加入群组后，进入主界面时展示一次性绑定账号引导。
enum AnonymousBindPromptStore {
    private static let pendingKey = "anonymous_bind_prompt_pending"

    static func scheduleAfterGroupAction() {
        UserDefaults.standard.set(true, forKey: pendingKey)
    }

    static func consumeIfPending() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return false }
        UserDefaults.standard.set(false, forKey: pendingKey)
        return true
    }
}
