import Foundation
import Security

/// Keychain 中独立槽位持久化 Auth session token（游客 / 正式互不覆盖）。
enum PersistedAuthSessionKeychain {
    enum Slot: String {
        case guest
        case formal

        fileprivate var service: String {
            switch self {
            case .guest:
                return "com.wesync.guest-session-archive"
            case .formal:
                return "com.wesync.formal-session-archive"
            }
        }

        fileprivate var account: String {
            switch self {
            case .guest:
                return "anonymous-session"
            case .formal:
                return "registered-session"
            }
        }
    }

    struct Payload: Codable, Equatable {
        let userId: UUID
        let accessToken: String
        let refreshToken: String
    }

    static func save(_ payload: Payload, slot: Slot) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        clear(slot: slot)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: slot.service,
            kSecAttrAccount as String: slot.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(slot: Slot) -> Payload? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: slot.service,
            kSecAttrAccount as String: slot.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }
        return payload
    }

    static func clear(slot: Slot) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: slot.service,
            kSecAttrAccount as String: slot.account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
