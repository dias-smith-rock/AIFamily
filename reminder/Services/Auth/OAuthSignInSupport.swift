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
