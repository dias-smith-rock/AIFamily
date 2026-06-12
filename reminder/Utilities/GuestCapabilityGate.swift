import SwiftUI

enum GuestCapabilityError: LocalizedError {
    case requiresSignIn

    var errorDescription: String? {
        switch self {
        case .requiresSignIn:
            L10n.Auth.signInToUseThisFeatureAndSyncYourLocal.string()
        }
    }
}

private struct IsGuestModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isGuestMode: Bool {
        get { self[IsGuestModeKey.self] }
        set { self[IsGuestModeKey.self] = newValue }
    }
}

extension View {
    func guestSignInRequiredAlert(isPresented: Binding<Bool>) -> some View {
        alert(L10n.Auth.signInRequired, isPresented: isPresented) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(L10n.Auth.signInToUseCloudFeaturesAndSyncYourLoca.localized)
        }
    }
}

enum GuestCapability {
    static func blockIfGuest(_ isGuestMode: Bool) throws {
        guard isGuestMode == false else {
            throw GuestCapabilityError.requiresSignIn
        }
    }

    /// 游客模式下置 `isPresented = true` 并返回 `true`，调用方应中止云端数据库操作。
    @MainActor
    static func presentSignInRequiredIfGuest(isPresented: inout Bool) -> Bool {
        guard GuestSessionStore.isGuestMode else { return false }
        isPresented = true
        return true
    }
}
