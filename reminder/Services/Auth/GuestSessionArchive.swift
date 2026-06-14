import Foundation
import Security

/// 登录页 OAuth 切换正式账号前，归档 anonymous session token，供「游客试用」恢复同一 UUID。
enum GuestSessionArchive {
    private static let service = "com.wesync.guest-session-archive"
    private static let account = "anonymous-session"

    struct Payload: Codable, Equatable {
        let userId: UUID
        let accessToken: String
        let refreshToken: String
    }

    static func save(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> Payload? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
