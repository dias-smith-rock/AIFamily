import Foundation

/// 记录用户是否曾成功登录，用于冷启动时决定是否展示会话恢复动画。
enum AuthSessionHints {
    private static let everAuthenticatedKey = "aifamily.hasEverAuthenticated"

    static var hasEverAuthenticated: Bool {
        UserDefaults.standard.bool(forKey: everAuthenticatedKey)
    }

    static func markEverAuthenticated() {
        UserDefaults.standard.set(true, forKey: everAuthenticatedKey)
    }
}
