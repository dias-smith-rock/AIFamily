import SwiftUI

private struct IsAnonymousUserKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Supabase 匿名会话（`user.isAnonymous == true`）。
    var isAnonymousUser: Bool {
        get { self[IsAnonymousUserKey.self] }
        set { self[IsAnonymousUserKey.self] = newValue }
    }
}

enum LegacyGuestDataCleaner {
    /// 一次性清理旧版本地试用 UserDefaults（无 Supabase 会话）。
    static func removeLegacyLocalTrialKeysIfNeeded() {
        UserDefaults.standard.removeObject(forKey: "isGuestMode")
        UserDefaults.standard.removeObject(forKey: "guest.workspace.snapshot")
        LocalCacheManager.shared.remove(forKey: "guest.workspace.snapshot")
    }
}

/// 解析持久化在库中的 String Catalog 键（如 `common.me`）为当前语言展示名。
enum StoredDisplayNameResolver {
    static func householdName(_ storedName: String?) -> String {
        let trimmed = storedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return trimmed }
        if trimmed == L10n.Common.mySpace.key {
            return AppLocalized.localizedSync(L10n.Common.mySpace)
        }
        return trimmed
    }

    static func selfName(_ storedName: String?, locale: Locale? = nil) -> String {
        let trimmed = storedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return trimmed }
        if trimmed == L10n.Common.me.key {
            return locale.map { AppLocalized.string(L10n.Common.me, locale: $0) }
                ?? AppLocalized.localizedSync(L10n.Common.me)
        }
        if trimmed == L10n.Family.newMember.key || trimmed == "New member" || trimmed == "新成员" {
            return locale.map { AppLocalized.string(L10n.Family.newMember, locale: $0) }
                ?? AppLocalized.localizedSync(L10n.Family.newMember)
        }
        return trimmed
    }
}
