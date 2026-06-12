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
    @Published private(set) var statusText = AppLocalized.localized(L10n.Auth.signInToEnableCloudSync)
    @Published private(set) var isLoggedIn = false

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    func refreshSessionState() async {
        isLoggedIn = await authService.hasValidSession()
        if isLoggedIn {
            statusText = AppLocalized.localized(L10n.Auth.aValidSignInSessionWasDetected)
            UserDefaults.standard.set(true, forKey: "isUserLoggedIn")
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
                    ? AppLocalized.localized(L10n.Auth.signedInWithApple)
                    : AppLocalized.localized(L10n.Auth.signInRequestSentCompleteAuthorizationAnd)
                if isLoggedIn {
                    UserDefaults.standard.set(true, forKey: "isUserLoggedIn")
                    AnalyticsManager.logAuthSessionSucceeded()
                }
            case .magicLink:
                try await authService.sendMagicLink(email: email)
                isLoggedIn = await authService.hasValidSession()
                statusText = isLoggedIn
                    ? AppLocalized.localized(L10n.Auth.signedInSuccessfully)
                    : AppLocalized.localized(L10n.Auth.signInLinkSentCheckYourEmailAndReturnTo)
                if isLoggedIn {
                    UserDefaults.standard.set(true, forKey: "isUserLoggedIn")
                    AnalyticsManager.logAuthSessionSucceeded()
                }
            case .phoneOTP:
                try await authService.sendPhoneOTP(phoneNumber: phone)
                isLoggedIn = await authService.hasValidSession()
                statusText = isLoggedIn
                    ? AppLocalized.localized(L10n.Auth.signedInSuccessfully)
                    : AppLocalized.localized(L10n.Common.verificationCodeSentCompleteVerificationAnd)
                if isLoggedIn {
                    UserDefaults.standard.set(true, forKey: "isUserLoggedIn")
                    AnalyticsManager.logAuthSessionSucceeded()
                }
            }
        } catch {
            statusText = error.localizedDescription
        }
    }
}
