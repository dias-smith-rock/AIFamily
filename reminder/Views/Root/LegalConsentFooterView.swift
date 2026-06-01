import SwiftUI

/// 登录等场景底部：说明继续操作即表示同意，并提供隐私政策 / 用户协议入口。
struct LegalConsentFooterView: View {
    var onPrivacy: () -> Void
    var onTerms: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("登录即表示您同意本 App 的")
                .foregroundStyle(secondaryText)
            HStack(spacing: 4) {
                linkButton("隐私政策", action: onPrivacy)
                Text("和")
                    .foregroundStyle(secondaryText)
                linkButton("用户协议", action: onTerms)
            }
        }
        .font(.system(size: 12, weight: .regular))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var secondaryText: Color {
        .white.opacity(0.55)
    }

    private func linkButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .underline()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        LegalConsentFooterView(onPrivacy: {}, onTerms: {})
            .padding(.horizontal, 24)
    }
}
