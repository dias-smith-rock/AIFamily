import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Supabase)
import Supabase
#endif

enum OAuthSignInSupport {
    static let oauthRedirectURL = URL(string: "aifamily://auth-callback")

    static func signInWithGoogleOAuth() async throws {
        #if canImport(Supabase)
        try await SupabaseManager.shared.client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: oauthRedirectURL,
            queryParams: [
                (name: "prompt", value: "select_account"),
                (name: "access_type", value: "offline"),
            ]
        )
        #else
        throw NSError(domain: "OAuthSignInSupport", code: -1)
        #endif
    }

    /// 游客 `linkIdentity` 须在 App 内完成 OAuth（与 `signInWithOAuth` 一致），避免 `UIApplication.open` 跳出 App。
    #if canImport(AuthenticationServices) && canImport(UIKit)
    @MainActor
    static func presentInAppOAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            guard let callbackScheme = oauthRedirectURL?.scheme else {
                continuation.resume(throwing: OAuthSignInSupportError.missingRedirectURL)
                return
            }

            let presentationContextProvider = OAuthWebAuthenticationPresentationContextProvider()
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: OAuthSignInSupportError.missingCallbackURL)
                }
                _ = presentationContextProvider
            }

            session.presentationContextProvider = presentationContextProvider
            session.start()
        }
    }
    #endif

    /// Maps GoTrue errors (e.g. manual linking disabled) to localized user-facing copy.
    static func userFacingMessage(for error: Error, locale: Locale) -> String {
        if isIdentityAlreadyLinked(error) {
            return AppLocalized.string(L10n.Auth.identityAlreadyLinkedMessage, locale: locale)
        }
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("manual linking is disabled") {
            return AppLocalized.string(L10n.Auth.manualLinkingDisabled, locale: locale)
        }
        return raw
    }

    /// GoTrue rejects linking when OAuth identity belongs to another auth user.
    static func isIdentityAlreadyLinked(_ error: Error) -> Bool {
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("already linked to another user") {
            return true
        }
        if raw.localizedCaseInsensitiveContains("identity is already linked") {
            return true
        }
        if raw.localizedCaseInsensitiveContains("identity_already_exists") {
            return true
        }
        return false
    }

    static func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession", nsError.code == 1 {
            return true
        }
        #if canImport(AuthenticationServices)
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            return true
        }
        #endif
        return false
    }
}

private enum OAuthSignInSupportError: Error {
    case missingRedirectURL
    case missingCallbackURL
}

#if canImport(AuthenticationServices) && canImport(UIKit)
@MainActor
private final class OAuthWebAuthenticationPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let firstWindow = scenes.first?.windows.first {
            return firstWindow
        }
        if let firstScene = scenes.first {
            return ASPresentationAnchor(windowScene: firstScene)
        }
        if
            let anyScene = UIApplication.shared.connectedScenes.first,
            let windowScene = anyScene as? UIWindowScene
        {
            return ASPresentationAnchor(windowScene: windowScene)
        }
        return ASPresentationAnchor()
    }
}
#endif
