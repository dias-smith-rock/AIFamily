import SwiftUI

/// 曾登录用户冷启动恢复会话时的过渡页，避免先闪登录页再跳转主界面。
struct SessionRestoreView: View {
    @Environment(\.locale) private var locale
    @State private var isLogoPulsing = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80)

            VStack(spacing: 18) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 82, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .scaleEffect(isLogoPulsing ? 1.05 : 1)
                    .animation(
                        .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: isLogoPulsing
                    )
                Text(L10n.Common.fromChaosToClarityTogetherPerfectlySynced.localized)
                    .font(AppTheme.FontToken.subtitle)
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 120)

            VStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.1)
                Text(AppLocalized.string(L10n.Auth.signingIn, locale: locale))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 100)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            isLogoPulsing = true
        }
    }
}

#Preview {
    SessionRestoreView()
        .environmentObject(AppSettingsManager.shared)
}
