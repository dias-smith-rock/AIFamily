import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(Supabase)
import Supabase
#endif

struct LoginView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @AppStorage("isUserLoggedIn") private var isUserLoggedIn = false
    @AppStorage(GuestSessionStore.isGuestModeKey) private var isGuestMode = false
    @State private var loadingProvider: LoginProvider?
    @State private var appleSignInPresenter = AppleSignInPresenter()
    @State private var loginErrorAlert: String?
    @State private var showPrivacySheet = false
    @State private var showTermsSheet = false

    private enum LoginProvider {
        case apple
        case google
    }

    /// 必须与 `supabase/config.toml` 中 `[auth].additional_redirect_urls` 完全一致，
    /// 同时也需要在 Info.plist 的 URL Types 中注册 `aifamily` scheme。
    private static let oauthRedirectURL = URL(string: "aifamily://auth-callback")

    /// 是否展示底部「More」登录入口（暂时关闭）。
    private let showsMoreLoginEntry = false

    /// 是否展示游客试用入口（暂时关闭）。
    private let showsGuestModeEntry = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80)
            brandSection
            Spacer(minLength: 120)
            actionSection
            Spacer(minLength: 40)
            if showsMoreLoginEntry {
                moreEntry
            }
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LegalConsentFooterView(
                onPrivacy: { showPrivacySheet = true },
                onTerms: { showTermsSheet = true }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showTermsSheet) {
            if let url = SupportLegalLinks.termsOfService {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            if let url = SupportLegalLinks.privacyPolicy {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .alert(L10n.Auth.unableToCompleteLogin, isPresented: Binding(
            get: { loginErrorAlert != nil },
            set: { if $0 == false { loginErrorAlert = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(loginErrorAlert ?? "")
        }
        // 保留：处理 Magic Link 邮件回跳等非 ASWebAuthenticationSession 场景
        .onOpenURL { url in
            handleAuthCallback(url)
        }
    }

    private var brandSection: some View {
        VStack(spacing: 18) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Text(L10n.Common.fromChaosToClarityTogetherPerfectlySynced.localized)
                .font(AppTheme.FontToken.subtitle)
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            OAuthGoogleSignInButton(
                title: L10n.Common.continueWithGoogle.localized,
                isLoading: loadingProvider == .google,
                action: triggerGoogleLogin
            )
            .disabled(loadingProvider != nil)

            #if canImport(Supabase) && canImport(AuthenticationServices)
            OAuthAppleSignInButton(
                title: L10n.Auth.continueWithApple.localized,
                isLoading: loadingProvider == .apple,
                action: triggerAppleSignIn
            )
            .disabled(loadingProvider != nil)
            #else
            Text(AppLocalized.string(L10n.Auth.appleSupabaseUnavailableUseGoogle, locale: locale))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            #endif

            if showsGuestModeEntry {
                Button {
                    startGuestMode()
                } label: {
                    Text(L10n.Auth.tryWithoutSigningIn.localized)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(loadingProvider != nil)
                .padding(.top, 4)
            }
        }
    }

    private var moreEntry: some View {
        Button {
            // 预留更多登录方式入口
        } label: {
            Text(L10n.Common.more.localized)
                .font(.system(size: 31 / 2, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    #if canImport(Supabase) && canImport(AuthenticationServices)
    private func triggerAppleSignIn() {
        appleSignInPresenter.onComplete = { result in
            handleAppleAuthorization(result)
        }
        appleSignInPresenter.performRequests()
    }
    #endif

    private func triggerGoogleLogin() {
        Task {
            await MainActor.run {
                loginErrorAlert = nil
                loadingProvider = .google
            }
            do {
                try await signInWithGoogleOAuth()
                try await settlePostOAuthState()
            } catch {
                if isUserCancelled(error) == false {
                    await MainActor.run {
                        loginErrorAlert = error.localizedDescription
                    }
                }
            }
            await MainActor.run {
                loadingProvider = nil
            }
        }
    }

    #if canImport(Supabase) && canImport(AuthenticationServices)
    private func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        Task {
            await MainActor.run {
                loginErrorAlert = nil
                loadingProvider = .apple
            }
            await performAppleSignIn(result)
            await MainActor.run {
                loadingProvider = nil
            }
        }
    }

    private func performAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if isUserCancelled(error) == false {
                await MainActor.run {
                    loginErrorAlert = error.localizedDescription
                }
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                await MainActor.run {
                    loginErrorAlert = AppLocalized.string(L10n.Auth.appleCredentialReadFailed, locale: locale)
                }
                return
            }
            guard let tokenData = credential.identityToken,
                  let idTokenString = String(data: tokenData, encoding: .utf8)
            else {
                await MainActor.run {
                    loginErrorAlert = AppLocalized.string(L10n.Auth.appleIdentityTokenFailed, locale: locale)
                }
                return
            }
            guard let rawNonce = appleSignInPresenter.currentRawNonce else {
                await MainActor.run {
                    loginErrorAlert = AppLocalized.string(L10n.Auth.sessionAbnormalRetry, locale: locale)
                }
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
                try await settlePostOAuthState()
            } catch {
                if isUserCancelled(error) == false {
                    await MainActor.run {
                        loginErrorAlert = error.localizedDescription
                    }
                }
            }
        }
    }
    #endif

    /// 走 supabase-swift 的内置 `signInWithOAuth`：iOS 上会用 `ASWebAuthenticationSession`
    /// 在当前 App 内弹出 Safari View 卡片完成登录，回跳由 SDK 内部接管，不需要 `onOpenURL`。
    private func signInWithGoogleOAuth() async throws {
        try await OAuthSignInSupport.signInWithGoogleOAuth()
    }

    /// 用户在 Safari View 卡片里点了L10n.Common.cancel会抛 `ASWebAuthenticationSessionError.canceledLogin`，
    /// 这是正常交互而非错误，不要把它显示成红字提示。
    private func isUserCancelled(_ error: Error) -> Bool {
        OAuthSignInSupport.isUserCancelled(error)
    }

    /// 兜底：处理 Magic Link 等通过 URL Scheme 直接拉起 App 的回跳。
    private func handleAuthCallback(_ url: URL) {
        #if canImport(Supabase)
        Task {
            do {
                _ = try await SupabaseManager.shared.client.auth.session(from: url)
                try await settlePostOAuthState()
            } catch {
                await MainActor.run {
                    loginErrorAlert = error.localizedDescription
                }
            }
        }
        #else
        _ = url
        #endif
    }

    /// OAuth 结束后，Auth 会话与 RLS 可见性在本地可能有短暂传播延迟。
    /// 这里做轻量重试，避免刚回调就误判成未登录，留在登录页。
    private func settlePostOAuthState() async throws {
        let migrationFailed = try await OAuthSessionCoordinator.settleAfterOAuth(
            appRouter: appRouter,
            appBootstrap: appBootstrap,
            migrationFailureHandler: { message in
                loginErrorAlert = message
            }
        )
        await MainActor.run {
            withAnimation(.easeInOut) {
                isUserLoggedIn = true
                isGuestMode = migrationFailed && GuestSessionStore.hasPendingSnapshot
            }
        }
    }

    private func startGuestMode() {
        let snapshot = GuestSessionStore.loadOrCreate()
        GuestSessionStore.setGuestMode(true)
        appBootstrap.enterGuestMode()
        appRouter.enterGuestMode(snapshot: snapshot)
        withAnimation(.easeInOut) {
            isGuestMode = true
        }
        AnalyticsManager.log(event: .guestStarted)
    }
}

#Preview {
    LoginView()
        .environmentObject(AppRouter())
        .environmentObject(AppBootstrap())
}
