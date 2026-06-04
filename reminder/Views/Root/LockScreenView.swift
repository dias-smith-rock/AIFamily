import SwiftUI

struct LockScreenView: View {
    let isAuthenticatingBiometrics: Bool
    let isAuthenticatingPasscode: Bool
    let onUnlockWithBiometrics: () -> Void
    let onUnlockWithPasscode: () -> Void

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
                onUnlockWithBiometrics()
            } label: {
                if isAuthenticatingBiometrics {
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
            .disabled(isAuthenticatingBiometrics || isAuthenticatingPasscode)
            .padding(.horizontal, 24)

            Button {
                onUnlockWithPasscode()
            } label: {
                if isAuthenticatingPasscode {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                } else {
                    Label("使用设备密码解锁", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isAuthenticatingBiometrics || isAuthenticatingPasscode)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.background.ignoresSafeArea())
    }
}

#Preview {
    LockScreenView(
        isAuthenticatingBiometrics: false,
        isAuthenticatingPasscode: false,
        onUnlockWithBiometrics: {},
        onUnlockWithPasscode: {}
    )
}
