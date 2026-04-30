import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var loadingProvider: LoginProvider?

    private enum LoginProvider {
        case apple
        case google
    }

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

    private func triggerLogin(_ provider: LoginProvider) {
        loadingProvider = provider
        _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
            await appRouter.refreshStateFromBackend()
            loadingProvider = nil
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppRouter())
}
