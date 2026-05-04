import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct LoginView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var loadingProvider: LoginProvider?
    @State private var errorMessage: String?

    private enum LoginProvider {
        case apple
        case google
    }

    /// 必须与 `supabase/config.toml` 中 `[auth].additional_redirect_urls` 完全一致，
    /// 同时也需要在 Info.plist 的 URL Types 中注册 `aifamily` scheme。
    private static let oauthRedirectURL = URL(string: "aifamily://login-callback")

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80)
            brandSection
            Spacer(minLength: 120)
            actionSection
            Spacer(minLength: 40)
            moreEntry
            Spacer(minLength: 100)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
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
            Text("From chaos to clarity.\nPrecision care for every family.")
                .font(.system(size: 16, weight: .medium))
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

            loginButton(
                title: "Sign in with Apple",
                icon: "apple.logo",
                provider: .apple,
                background: .clear,
                foreground: .white,
                border: .white.opacity(0.25)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
    }

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
        title: String,
        icon: String,
        provider: LoginProvider,
        background: Color,
        foreground: Color,
        border: Color
    ) -> some View {
        Button {
            triggerLogin(provider)
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

    private func triggerLogin(_ provider: LoginProvider) {
        errorMessage = nil
        loadingProvider = provider
        Task {
            do {
                try await signInWithOAuth(provider: provider)
                await appRouter.refreshStateFromBackend()
            } catch {
                if isUserCancelled(error) == false {
                    errorMessage = error.localizedDescription
                }
            }
            loadingProvider = nil
        }
    }

    /// 走 supabase-swift 的内置 `signInWithOAuth`：iOS 上会用 `ASWebAuthenticationSession`
    /// 在当前 App 内弹出 Safari View 卡片完成登录，回跳由 SDK 内部接管，不需要 `onOpenURL`。
    private func signInWithOAuth(provider: LoginProvider) async throws {
        #if canImport(Supabase)
        let oauthProvider: Provider = provider == .google ? .google : .apple
        try await SupabaseManager.shared.client.auth.signInWithOAuth(
            provider: oauthProvider,
            redirectTo: Self.oauthRedirectURL
        )
        #else
        _ = provider
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
        return nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession"
            && nsError.code == 1
    }

    /// 兜底：处理 Magic Link 等通过 URL Scheme 直接拉起 App 的回跳。
    private func handleAuthCallback(_ url: URL) {
        #if canImport(Supabase)
        Task {
            do {
                _ = try await SupabaseManager.shared.client.auth.session(from: url)
                await appRouter.refreshStateFromBackend()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        #else
        _ = url
        #endif
    }
}

#Preview {
    LoginView()
        .environmentObject(AppRouter())
}
