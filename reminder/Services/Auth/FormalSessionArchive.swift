import Foundation

/// 正式账号 session token 的 Keychain 槽位（与游客槽位独立）。
enum FormalSessionArchive {
    typealias Payload = PersistedAuthSessionKeychain.Payload

    static func save(_ payload: Payload) {
        PersistedAuthSessionKeychain.save(payload, slot: .formal)
    }

    static func load() -> Payload? {
        PersistedAuthSessionKeychain.load(slot: .formal)
    }

    static func clear() {
        PersistedAuthSessionKeychain.clear(slot: .formal)
    }
}
