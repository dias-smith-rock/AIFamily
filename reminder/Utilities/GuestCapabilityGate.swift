import SwiftUI

enum GuestCapabilityError: LocalizedError {
    case requiresSignIn

    var errorDescription: String? {
        switch self {
        case .requiresSignIn:
            String(localized: "登录后可使用此功能，并同步本地数据。")
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
        alert("需要登录", isPresented: isPresented) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("登录后可使用云端功能，并同步本地数据。")
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
