import Foundation

/// 游客 session token 的 Keychain 槽位（与正式账号槽位独立）。
enum GuestSessionArchive {
    typealias Payload = PersistedAuthSessionKeychain.Payload

    static func save(_ payload: Payload) {
        PersistedAuthSessionKeychain.save(payload, slot: .guest)
    }

    static func load() -> Payload? {
        PersistedAuthSessionKeychain.load(slot: .guest)
    }

    static func clear() {
        PersistedAuthSessionKeychain.clear(slot: .guest)
    }

    /// 是否已在 Keychain 中备份过游客 access / refresh token。
    static var hasSavedTokens: Bool {
        guard let payload = load() else { return false }
        return payload.accessToken.isEmpty == false && payload.refreshToken.isEmpty == false
    }
}
