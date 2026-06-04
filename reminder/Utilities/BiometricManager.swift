import SwiftUI
import Combine
import LocalAuthentication
import Security

@MainActor
final class BiometricManager: ObservableObject {
    @AppStorage("requireFaceID") var requireFaceID: Bool = false
    @Published var isUnlocked: Bool = false
    @Published private(set) var isAuthenticating = false

    func authenticateWithBiometrics() {
        performAuthentication(policy: .deviceOwnerAuthenticationWithBiometrics)
    }

    func authenticateWithPasscode() {
        guard isAuthenticating == false else { return }
        guard requireFaceID else {
            withAnimation(.easeInOut) {
                isUnlocked = true
            }
            return
        }

        isAuthenticating = true
        Task {
            defer { isAuthenticating = false }
            let reason = String(localized: "请验证身份以访问同圈中的家庭日程与任务。")
            let cancelTitle = String(localized: "稍后")
            let success = await DevicePasscodeUnlockProbe.authenticate(
                reason: reason,
                cancelTitle: cancelTitle
            )
            withAnimation(.easeInOut) {
                isUnlocked = success
            }
        }
    }

    /// 设置页开启面部解锁前校验；验证通过才应写入 `requireFaceID = true`。
    func verifyEnrollmentForSettings() async -> Bool {
        await evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, reasonKey: "请验证身份以开启面部解锁。")
    }

    private func performAuthentication(policy: LAPolicy) {
        guard isAuthenticating == false else { return }
        guard requireFaceID else {
            withAnimation(.easeInOut) {
                isUnlocked = true
            }
            return
        }

        isAuthenticating = true
        Task {
            defer { isAuthenticating = false }
            let success = await evaluatePolicy(
                policy,
                reasonKey: "请验证身份以访问同圈中的家庭日程与任务。"
            )
            withAnimation(.easeInOut) {
                isUnlocked = success
            }
        }
    }

    private func evaluatePolicy(_ policy: LAPolicy, reasonKey: String.LocalizationValue) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "稍后")
        let reason = String(localized: reasonKey)

        var authError: NSError?
        guard context.canEvaluatePolicy(policy, error: &authError) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }

    func lockIfNeeded() {
        guard requireFaceID else { return }
        isUnlocked = false
    }
}

// MARK: - Device passcode only (Keychain)

/// 通过仅允许「设备密码」的 Keychain 访问控制触发系统密码键盘，避免 `deviceOwnerAuthentication` 先走 Face ID。
private enum DevicePasscodeUnlockProbe {
    static let service = "com.aifamilygroup.reminder.unlock-passcode-probe"
    static let account = "device-passcode-unlock"

    static func authenticate(reason: String, cancelTitle: String) async -> Bool {
        guard ensureProbeExists() else { return false }

        let context = LAContext()
        context.localizedReason = reason
        context.localizedCancelTitle = cancelTitle

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        return await Task.detached(priority: .userInitiated) {
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            switch status {
            case errSecSuccess:
                return true
            case errSecUserCanceled, errSecAuthFailed:
                return false
            default:
                return false
            }
        }.value
    }

    private static func ensureProbeExists() -> Bool {
        let existsQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
        ]

        var item: CFTypeRef?
        let existsStatus = SecItemCopyMatching(existsQuery as CFDictionary, &item)
        if existsStatus == errSecSuccess {
            return true
        }
        if existsStatus != errSecItemNotFound {
            return false
        }

        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .devicePasscode,
            &accessError
        ) else {
            return false
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: accessControl,
            kSecValueData as String: Data([1]),
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess || addStatus == errSecDuplicateItem
    }
}
