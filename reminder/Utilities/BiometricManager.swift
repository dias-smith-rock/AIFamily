import SwiftUI
import Combine
import LocalAuthentication
import Security

@MainActor
final class BiometricManager: ObservableObject {
    @AppStorage("requireFaceID") var requireFaceID: Bool = false
    @Published var isUnlocked: Bool = false
    @Published private(set) var isAuthenticatingBiometrics = false
    @Published private(set) var isAuthenticatingPasscode = false
    @Published private(set) var lockPresentationGeneration = 0

    var isAuthenticating: Bool {
        isAuthenticatingBiometrics || isAuthenticatingPasscode
    }

    private var authGeneration = 0

    func authenticateWithBiometrics() {
        startAuthentication(mode: .biometrics, chainPasscodeOnFailure: false)
    }

    func authenticateWithPasscode() {
        startAuthentication(mode: .passcode, chainPasscodeOnFailure: false)
    }

    /// 锁屏出现时：先 Face ID，识别失败（非用户取消）再自动弹出设备密码。
    func performAutoUnlockOnLockScreen() {
        startAuthentication(mode: .biometrics, chainPasscodeOnFailure: true)
    }

    /// 设置页开启面部解锁前校验；验证通过才应写入 `requireFaceID = true`。
    func verifyEnrollmentForSettings() async -> Bool {
        let (success, _) = await evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            reasonKey: "请验证身份以开启面部解锁。"
        )
        return success
    }

    func lockIfNeeded() {
        guard requireFaceID else { return }
        guard isAuthenticating == false else { return }
        if isUnlocked {
            lockPresentationGeneration += 1
        }
        isUnlocked = false
    }

    private enum AuthenticationMode {
        case biometrics
        case passcode
    }

    private func startAuthentication(mode: AuthenticationMode, chainPasscodeOnFailure: Bool) {
        switch mode {
        case .biometrics:
            guard isAuthenticatingBiometrics == false else { return }
        case .passcode:
            guard isAuthenticatingPasscode == false else { return }
        }

        guard requireFaceID else {
            withAnimation(.easeInOut) {
                isUnlocked = true
            }
            return
        }

        authGeneration += 1
        let generation = authGeneration

        switch mode {
        case .biometrics:
            isAuthenticatingBiometrics = true
            isAuthenticatingPasscode = false
        case .passcode:
            isAuthenticatingPasscode = true
            isAuthenticatingBiometrics = false
        }

        Task { @MainActor in
            let reasonKey: String.LocalizationValue = "请验证身份以访问同圈中的家庭日程与任务。"
            let unlocked: Bool

            switch mode {
            case .biometrics:
                let (success, error) = await evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    reasonKey: reasonKey
                )
                if success {
                    unlocked = true
                } else if chainPasscodeOnFailure, shouldOfferPasscodeAfterBiometricsFailure(error) {
                    isAuthenticatingBiometrics = false
                    isAuthenticatingPasscode = true
                    unlocked = authenticateWithDevicePasscodeOnly(reasonKey: reasonKey)
                } else {
                    unlocked = false
                }
            case .passcode:
                unlocked = authenticateWithDevicePasscodeOnly(reasonKey: reasonKey)
            }

            guard authGeneration == generation else { return }

            isAuthenticatingBiometrics = false
            isAuthenticatingPasscode = false
            withAnimation(.easeInOut) {
                isUnlocked = unlocked
            }
        }
    }

    private func authenticateWithDevicePasscodeOnly(reasonKey: String.LocalizationValue) -> Bool {
        let reason = String(localized: reasonKey)
        return DevicePasscodeUnlockProbe.authenticate(reason: reason)
    }

    private func shouldOfferPasscodeAfterBiometricsFailure(_ error: Error?) -> Bool {
        guard let error else { return true }
        guard let laError = error as? LAError else { return true }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel:
            return false
        default:
            return true
        }
    }

    private func evaluatePolicy(
        _ policy: LAPolicy,
        reasonKey: String.LocalizationValue
    ) async -> (success: Bool, error: Error?) {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "稍后")
        let reason = String(localized: reasonKey)

        var authError: NSError?
        guard context.canEvaluatePolicy(policy, error: &authError) else {
            return (false, authError)
        }

        if #available(iOS 15.0, *) {
            do {
                try await context.evaluatePolicy(policy, localizedReason: reason)
                return (true, nil)
            } catch {
                return (false, error)
            }
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { ok, error in
                continuation.resume(returning: (ok, error))
            }
        }
    }
}

// MARK: - Device passcode only (Keychain)

/// 通过 `devicePasscode` 访问控制触发系统设备密码界面，避免 `deviceOwnerAuthentication` 再次调起 Face ID。
private enum DevicePasscodeUnlockProbe {
    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "com.aifamilygroup.reminder") + ".device-passcode-unlock"
    }

    private static let account = "unlock-probe-v1"

    static func authenticate(reason: String) -> Bool {
        ensureInstalled()
        let context = LAContext()
        context.localizedReason = reason

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess
    }

    private static func ensureInstalled() {
        let existsQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if SecItemCopyMatching(existsQuery as CFDictionary, nil) == errSecSuccess {
            return
        }
        installProbe()
    }

    private static func installProbe() {
        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .devicePasscode,
            &accessError
        ) else {
            return
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data("1".utf8),
            kSecAttrAccessControl as String: accessControl,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
