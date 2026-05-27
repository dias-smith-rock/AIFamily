import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    enum LoginMethod: String, CaseIterable, Identifiable {
        case apple = "Apple"
        case magicLink = "Magic Link"
        case phoneOTP = "Phone OTP"

        var id: String { rawValue }
    }

    @Published var selectedMethod: LoginMethod = .apple
    @Published var email = ""
    @Published var phone = ""
    @Published private(set) var isLoading = false
    @Published private(set) var statusText = AppLocalized.localized("请先登录以启用云端同步")
    @Published private(set) var isLoggedIn = false

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    func refreshSessionState() async {
        isLoggedIn = await authService.hasValidSession()
        if isLoggedIn {
            statusText = AppLocalized.localized("已检测到有效登录会话")
        }
    }

    func submit() async {
        isLoading = true
        defer { isLoading = false }
        do {
            switch selectedMethod {
            case .apple:
                try await authService.signInWithApple(
                    idToken: "mock-apple-token",
                    rawNonce: UUID().uuidString,
                    appleGivenName: nil,
                    appleFamilyName: nil,
                    appleEmail: nil
                )
                isLoggedIn = await authService.hasValidSession()
                statusText = isLoggedIn
                    ? AppLocalized.localized("Apple 登录成功")
                    : AppLocalized.localized("登录请求已发送，请完成授权后重试")
            case .magicLink:
                try await authService.sendMagicLink(email: email)
                isLoggedIn = await authService.hasValidSession()
                statusText = isLoggedIn
                    ? AppLocalized.localized("登录成功")
                    : AppLocalized.localized("登录链接已发送，请检查邮箱并回到 App")
            case .phoneOTP:
                try await authService.sendPhoneOTP(phoneNumber: phone)
                isLoggedIn = await authService.hasValidSession()
                statusText = isLoggedIn
                    ? AppLocalized.localized("登录成功")
                    : AppLocalized.localized("验证码已发送，请完成验证后重试")
            }
        } catch {
            statusText = error.localizedDescription
        }
    }
}
