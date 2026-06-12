import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(Supabase)
import Supabase
#endif

/// 游客态「我的」页：引导绑定 Apple / Google 并迁移本地数据。
struct GuestAccountLinkCard: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @Binding var isUserLoggedIn: Bool
    @Binding var isGuestMode: Bool

    @State private var loadingProvider: OAuthProvider?
    @State private var errorMessage: String?
    @State private var appleSignInPresenter = AppleSignInPresenter()

    private enum OAuthProvider {
        case apple
        case google
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Common.trialMode.localized)
                .font(.headline)
            Text(L10n.Auth.yourDataIsStoredOnThisDeviceOnlySignIn.localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                OAuthGoogleSignInButton(
                    title: L10n.Common.syncWithGoogle,
                    isLoading: loadingProvider == .google,
                    action: triggerGoogleLogin
                )
                .disabled(loadingProvider != nil)

                #if canImport(Supabase) && canImport(AuthenticationServices)
                OAuthAppleSignInButton(
                    title: L10n.Common.syncWithApple,
                    isLoading: loadingProvider == .apple,
                    action: triggerAppleSignIn
                )
                .disabled(loadingProvider != nil)
                #endif
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert(L10n.Auth.unableToCompleteLogin, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if $0 == false { errorMessage = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    #if canImport(Supabase) && canImport(AuthenticationServices)
    private func triggerAppleSignIn() {
        appleSignInPresenter.onComplete = { result in
            handleAppleAuthorization(result)
        }
        appleSignInPresenter.performRequests()
    }

    private func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        Task {
            loadingProvider = .apple
            defer { loadingProvider = nil }
            await performAppleSignIn(result)
        }
    }

    private func performAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if OAuthSignInSupport.isUserCancelled(error) == false {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = AppLocalized.string(L10n.Auth.appleCredentialReadFailed, locale: locale)
                return
            }
            guard let tokenData = credential.identityToken,
                  let idTokenString = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = AppLocalized.string(L10n.Auth.appleIdentityTokenFailed, locale: locale)
                return
            }
            guard let rawNonce = appleSignInPresenter.currentRawNonce else {
                errorMessage = AppLocalized.string(L10n.Auth.sessionAbnormalRetry, locale: locale)
                return
            }

            let provider = SupabaseProvider()
            let auth = SupabaseAuthService(
                provider: provider,
                avatarStorageService: SupabaseAvatarStorageService(provider: provider)
            )
            do {
                try await auth.signInWithApple(
                    idToken: idTokenString,
                    rawNonce: rawNonce,
                    appleGivenName: credential.fullName?.givenName,
                    appleFamilyName: credential.fullName?.familyName,
                    appleEmail: credential.email
                )
                try await completeSignIn()
            } catch {
                if OAuthSignInSupport.isUserCancelled(error) == false {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    #endif

    private func triggerGoogleLogin() {
        Task {
            loadingProvider = .google
            defer { loadingProvider = nil }
            do {
                try await OAuthSignInSupport.signInWithGoogleOAuth()
                try await completeSignIn()
            } catch {
                if OAuthSignInSupport.isUserCancelled(error) == false {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func completeSignIn() async throws {
        let migrationFailed = try await OAuthSessionCoordinator.settleAfterOAuth(
            appRouter: appRouter,
            appBootstrap: appBootstrap,
            migrationFailureHandler: { message in
                errorMessage = message
            }
        )
        withAnimation(.easeInOut) {
            isUserLoggedIn = true
            isGuestMode = migrationFailed && GuestSessionStore.hasPendingSnapshot
        }
    }
}

enum OAuthSignInSupport {
    static let oauthRedirectURL = URL(string: "aifamily://auth-callback")

    static func signInWithGoogleOAuth() async throws {
        #if canImport(Supabase)
        try await SupabaseManager.shared.client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: oauthRedirectURL,
            queryParams: [
                (name: "prompt", value: "select_account"),
                (name: "access_type", value: "offline")
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
