import Foundation
import Security

/// 小孩机家长 PIN 的本机缓存（Keychain）。权威值在服务端 `tracked_device_pin`，由管理员改后同步覆盖。
enum TrackedDevicePINStore {
    static let defaultPIN = "888888"

    private static let service = "com.wesync.tracked-device-pin"
    private static let account = "parent-pin"

    static func savePIN(_ pin: String) {
        let normalized = normalize(pin)
        if normalized.isEmpty {
            clear()
            return
        }
        guard (4 ... 6).contains(normalized.count) else { return }
        guard let data = normalized.data(using: .utf8) else { return }
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

    static func verify(_ pin: String) -> Bool {
        guard let stored = loadPIN() else { return false }
        return stored == normalize(pin)
    }

    static var hasPIN: Bool {
        loadPIN() != nil
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadPIN() -> String? {
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
              let pin = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return pin
    }

    static func normalize(_ pin: String) -> String {
        pin.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter(\.isNumber)
    }

    static func isValidFormat(_ pin: String) -> Bool {
        let normalized = normalize(pin)
        return (4 ... 6).contains(normalized.count)
    }

    /// 空 PIN 表示不设小孩机密码；否则须为 4–6 位数字。
    static func isAcceptableInput(_ pin: String) -> Bool {
        let normalized = normalize(pin)
        return normalized.isEmpty || (4 ... 6).contains(normalized.count)
    }
}
