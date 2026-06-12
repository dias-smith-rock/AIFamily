import SwiftUI

/// 登录等场景底部：说明继续操作即表示同意，并提供隐私政策 / 用户协议入口。
struct LegalConsentFooterView: View {
    var onPrivacy: () -> Void
    var onTerms: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(L10n.Auth.bySigningInYouAgreeToThisAppS.localized)
                .foregroundStyle(secondaryText)
            HStack(spacing: 4) {
                linkButton(L10n.Common.privacyPolicy, action: onPrivacy)
                Text(L10n.Common.and.localized)
                    .foregroundStyle(secondaryText)
                linkButton(L10n.Common.termsOfService, action: onTerms)
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
