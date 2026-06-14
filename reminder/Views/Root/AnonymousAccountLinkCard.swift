import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(Supabase)
import Supabase
#endif

/// Supabase 匿名用户转正：linkIdentity 保留 UUID，数据与订阅不丢失。
struct AnonymousAccountLinkCard: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter

    @State private var loadingProvider: OAuthProvider?
    @State private var errorMessage: String?
    @State private var showIdentityAlreadyLinkedAlert = false
    @State private var appleSignInPresenter = AppleSignInPresenter()
    var onLinked: () -> Void = {}

    private enum OAuthProvider {
        case apple
        case google
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(L10n.Auth.linkAccount.localized)
                    .font(.headline)
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
            }

            Text(L10n.Auth.anonymousAccountLinkSubtitle.localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                #if canImport(Supabase) && canImport(AuthenticationServices)
                OAuthAppleSignInButton(
                    title: L10n.Auth.bindAppleAccountKeepData.localized,
                    isLoading: loadingProvider == .apple,
                    action: triggerAppleLink
                )
                .disabled(loadingProvider != nil)
                #endif

                OAuthGoogleSignInButton(
                    title: L10n.Common.syncWithGoogle.localized,
                    isLoading: loadingProvider == .google,
                    action: triggerGoogleLink
                )
                .disabled(loadingProvider != nil)
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
        .alert(L10n.Auth.identityAlreadyLinkedTitle.localized, isPresented: $showIdentityAlreadyLinkedAlert) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(L10n.Auth.identityAlreadyLinkedMessage.localized)
        }
    }

    private func handleLinkFailure(_ error: Error) {
        if OAuthSignInSupport.isIdentityAlreadyLinked(error) {
            showIdentityAlreadyLinkedAlert = true
        } else {
            errorMessage = OAuthSignInSupport.userFacingMessage(for: error, locale: locale)
        }
    }

    #if canImport(Supabase) && canImport(AuthenticationServices)
    private func triggerAppleLink() {
        appleSignInPresenter.onComplete = { result in
            Task {
                loadingProvider = .apple
                defer { loadingProvider = nil }
                await performAppleLink(result)
            }
        }
        appleSignInPresenter.performRequests()
    }

    private func performAppleLink(_ result: Result<ASAuthorization, Error>) async {
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

            do {
                try await SupabaseAuthManager.linkAppleIdentity(
                    idToken: idTokenString,
                    rawNonce: rawNonce,
                    appRouter: appRouter
                )
                await appRouter.refreshStateFromBackend()
                onLinked()
            } catch {
                if OAuthSignInSupport.isUserCancelled(error) == false {
                    handleLinkFailure(error)
                }
            }
        }
    }
    #endif

    private func triggerGoogleLink() {
        Task {
            loadingProvider = .google
            defer { loadingProvider = nil }
            do {
                try await SupabaseAuthManager.linkGoogleIdentity(appRouter: appRouter)
                await appRouter.refreshStateFromBackend()
                onLinked()
            } catch {
                if OAuthSignInSupport.isUserCancelled(error) == false {
                    handleLinkFailure(error)
                }
            }
        }
    }
}
