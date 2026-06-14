import Foundation

/// 记录用户是否曾成功登录，用于冷启动时决定是否展示会话恢复动画。
enum AuthSessionHints {
    private static let everAuthenticatedKey = "aifamily.hasEverAuthenticated"
    private static let formalAccountUsedKey = "aifamily.hasEverUsedFormalAccount"
    /// 每次安装（含卸载重装）写入新的实例 ID；UserDefaults 清空即视为新安装。
    private static let installInstanceKey = "aifamily.installInstanceId"

    static var hasEverAuthenticated: Bool {
        UserDefaults.standard.bool(forKey: everAuthenticatedKey)
    }

    static func markEverAuthenticated() {
        UserDefaults.standard.set(true, forKey: everAuthenticatedKey)
    }

    /// 曾用 Google / Apple 等正式账号登录；此后登录页不再展示游客入口。
    /// 仅读 UserDefaults（卸载重装后会清空），不读 Keychain，避免 Keychain 残留误判。
    static var hasEverUsedFormalAccount: Bool {
        UserDefaults.standard.bool(forKey: formalAccountUsedKey)
    }

    /// 登录页是否展示「游客体验」入口。
    static var showsGuestLoginEntry: Bool {
        hasEverUsedFormalAccount == false
    }

    static func markFormalAccountUsed() {
        UserDefaults.standard.set(true, forKey: formalAccountUsedKey)
    }

    /// 冷启动首步：若 UserDefaults 无安装实例 ID，视为新安装/卸载重装，清理可能残留的 Auth Keychain 槽位。
    static func prepareForFreshInstallIfNeeded() {
        guard UserDefaults.standard.string(forKey: installInstanceKey) == nil else { return }

        UserDefaults.standard.set(UUID().uuidString, forKey: installInstanceKey)
        UserDefaults.standard.set(false, forKey: formalAccountUsedKey)
        GuestSessionArchive.clear()
        FormalSessionArchive.clear()
        #if DEBUG
        print("[AuthSessionHints] fresh install detected — cleared auth keychain archives, guest entry enabled")
        #endif
    }
}
