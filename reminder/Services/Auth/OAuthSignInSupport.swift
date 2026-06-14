import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
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
