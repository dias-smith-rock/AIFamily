import SwiftUI

/// 冷启动 Splash：恢复登录态与群组路由完成前展示，避免先闪任务主界面。
struct SessionRestoreView: View {
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
                Text(L10n.Common.loading.localized)
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
