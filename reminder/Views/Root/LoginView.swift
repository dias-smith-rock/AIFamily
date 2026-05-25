import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(Supabase)
import Supabase
#endif

struct LoginView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var loadingProvider: LoginProvider?
    @State private var appleRawNonce: String?
    @State private var loginErrorAlert: String?

    private enum LoginProvider {
        case apple
        case google
    }

    /// 必须与 `supabase/config.toml` 中 `[auth].additional_redirect_urls` 完全一致，
    /// 同时也需要在 Info.plist 的 URL Types 中注册 `aifamily` scheme。
    private static let oauthRedirectURL = URL(string: "aifamily://auth-callback")

    /// 是否展示底部「More」登录入口（暂时关闭）。
    private let showsMoreLoginEntry = false

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
            Spacer(minLength: 100)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .alert("无法完成登录", isPresented: Binding(
            get: { loginErrorAlert != nil },
            set: { if $0 == false { loginErrorAlert = nil } }
        )) {
            Button("好的", role: .cancel) {}
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
            Text("From chaos to clarity.\nTogether, perfectly synced.")
                .font(AppTheme.FontToken.subtitle)
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            loginButton(
                title: "Continue with Google",
                icon: "g.circle.fill",
                provider: .google,
                background: Color.blue,
                foreground: .white,
                border: .clear
            )

            #if canImport(Supabase) && canImport(AuthenticationServices)
            appleSignInControl
            #else
            Text("当前构建未启用 Sign in with Apple / Supabase，请使用 Google 登录。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            #endif
        }
    }

    #if canImport(Supabase) && canImport(AuthenticationServices)
    private var appleSignInControl: some View {
        ZStack {
            SignInWithAppleButton(.signIn) { request in
                let raw = AppleSignInHelper.generateRawNonce()
                appleRawNonce = raw
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleSignInHelper.sha256Hex(of: raw)
            } onCompletion: { result in
                handleAppleAuthorization(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if loadingProvider == .apple {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.35))
                ProgressView()
                    .tint(.white)
            }
        }
        .allowsHitTesting(loadingProvider == nil)
    }
    #endif

    private var moreEntry: some View {
        Button {
            // 预留更多登录方式入口
        } label: {
            Text("More")
                .font(.system(size: 31 / 2, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .buttonStyle(.plain)
    }

    private func loginButton(
        title: LocalizedStringKey,
        icon: String,
        provider: LoginProvider,
        background: Color,
        foreground: Color,
        border: Color
    ) -> some View {
        Button {
            triggerGoogleLogin()
        } label: {
            HStack(spacing: 10) {
                if loadingProvider == provider {
                    ProgressView()
                        .tint(foreground)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(loadingProvider != nil)
    }

    // MARK: - Actions

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
                    loginErrorAlert = "未能读取 Apple 登录凭证。"
                }
                return
            }
            guard let tokenData = credential.identityToken,
                  let idTokenString = String(data: tokenData, encoding: .utf8)
            else {
                await MainActor.run {
                    loginErrorAlert = "未能获取 Apple identity token。"
                }
                return
            }
            guard let rawNonce = appleRawNonce else {
                await MainActor.run {
                    loginErrorAlert = "登录状态异常，请重试。"
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
        #if canImport(Supabase)
        try await SupabaseManager.shared.client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: Self.oauthRedirectURL,
            queryParams: [
                (name: "prompt", value: "select_account"),
                (name: "access_type", value: "offline")
            ]
        )
        #else
        throw NSError(
            domain: "LoginView",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "当前构建环境未包含 Supabase SDK。"]
        )
        #endif
    }

    /// 用户在 Safari View 卡片里点了"取消"会抛 `ASWebAuthenticationSessionError.canceledLogin`，
    /// 这是正常交互而非错误，不要把它显示成红字提示。
    private func isUserCancelled(_ error: Error) -> Bool {
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
        #if canImport(Supabase)
        let maxAttempts = 8
        var hasValidSession = false
        for attempt in 1...maxAttempts {
            do {
                _ = try await SupabaseManager.shared.client.auth.session
                hasValidSession = true
                await appRouter.refreshStateFromBackend()
                if appRouter.appState != .unauthenticated {
                    return
                }
            } catch {
                if attempt == maxAttempts {
                    throw error
                }
            }

            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        if hasValidSession {
            // OAuth 已成功，但组织状态读取出现瞬时失败时，先放行到组织路由页，避免卡死登录。
            await MainActor.run {
                appRouter.goToOrgRouting()
            }
            return
        }

        throw NSError(
            domain: "LoginView",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "登录会话尚未就绪，请稍后重试。"]
        )
        #endif
    }
}

#Preview {
    LoginView()
        .environmentObject(AppRouter())
}
