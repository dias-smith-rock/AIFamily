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
            Text("试用模式")
                .font(.headline)
            Text("当前数据仅保存在本机。登录后可同步到云端，并与家人协作。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                triggerGoogleLogin()
            } label: {
                oauthButtonLabel(title: "使用 Google 同步", provider: .google)
            }
            .buttonStyle(.plain)
            .disabled(loadingProvider != nil)

            #if canImport(Supabase) && canImport(AuthenticationServices)
            Button {
                triggerAppleSignIn()
            } label: {
                oauthButtonLabel(title: "通过 Apple 同步", provider: .apple)
            }
            .buttonStyle(.plain)
            .disabled(loadingProvider != nil)
            #endif
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert("无法完成登录", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if $0 == false { errorMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func oauthButtonLabel(title: LocalizedStringKey, provider: OAuthProvider) -> some View {
        HStack(spacing: 10) {
            if loadingProvider == provider {
                ProgressView()
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                errorMessage = AppLocalized.string("未能读取 Apple 登录凭证。", locale: locale)
                return
            }
            guard let tokenData = credential.identityToken,
                  let idTokenString = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = AppLocalized.string("未能获取 Apple identity token。", locale: locale)
                return
            }
            guard let rawNonce = appleSignInPresenter.currentRawNonce else {
                errorMessage = AppLocalized.string("登录状态异常，请重试。", locale: locale)
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
