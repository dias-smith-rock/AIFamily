import SwiftUI

struct LockScreenView: View {
    let isAuthenticating: Bool
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("已锁定")
                .font(.title2.weight(.semibold))

            Text("使用 Face ID 解锁后继续访问你的家庭日程与任务。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                onUnlock()
            } label: {
                if isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    Label("使用 Face ID 解锁", systemImage: "faceid")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.background.ignoresSafeArea())
    }
}

#Preview {
    LockScreenView(isAuthenticating: false, onUnlock: {})
}
