import SwiftUI

/// 免费版触达配额上限时的统一升级提示（`.alert` + 跳转 VIP 页）。
struct PremiumUpgradeAlertModifier: ViewModifier {
    @EnvironmentObject private var appRouter: AppRouter
    @Binding var isPresented: Bool
    let message: LocalizedStringKey

    func body(content: Content) -> some View {
        content
            .alert("需要 Pro 会员", isPresented: $isPresented) {
                Button("升级 VIP") {
                    appRouter.presentPremiumUpgrade()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

extension View {
    func premiumUpgradeAlert(
        isPresented: Binding<Bool>,
        message: LocalizedStringKey
    ) -> some View {
        modifier(PremiumUpgradeAlertModifier(isPresented: isPresented, message: message))
    }
}
