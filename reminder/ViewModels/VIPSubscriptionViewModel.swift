import Combine
import Foundation
import SwiftUI

enum VIPBillingPlan: String, CaseIterable, Identifiable {
    case monthly
    case yearly

    var id: String { rawValue }

    var subscriptionPlan: SubscriptionPlan {
        switch self {
        case .monthly: .proMonthly
        case .yearly: .proYearly
        }
    }

    var priceText: String {
        switch self {
        case .monthly: "$4.99"
        case .yearly: "$39.99"
        }
    }

    var periodLabel: LocalizedStringKey {
        switch self {
        case .monthly: "每月"
        case .yearly: "每年"
        }
    }

    var planTitle: LocalizedStringKey {
        switch self {
        case .monthly: "月付"
        case .yearly: "年付"
        }
    }

    var isRecommended: Bool {
        self == .yearly
    }

    var savingsBadge: LocalizedStringKey? {
        isRecommended ? "省 33%" : nil
    }
}

@MainActor
final class VIPSubscriptionViewModel: ObservableObject {
    @Published var selectedPlan: VIPBillingPlan = .yearly
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    func purchaseSubscription(appRouter: AppRouter) async {
        guard appRouter.hasPremiumAccess == false else {
            errorMessage = AppLocalized.localized("您已是 Pro 会员。")
            return
        }
        guard isPurchasing == false else { return }

        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        // TODO: StoreKit 2 — 按 selectedPlan.subscriptionPlan 发起内购并回写 Supabase
        errorMessage = AppLocalized.localized("App Store 订阅功能即将上线，敬请期待。")
    }

    func restorePurchases(appRouter: AppRouter) async {
        guard appRouter.hasPremiumAccess == false else { return }
        errorMessage = AppLocalized.localized("App Store 订阅功能即将上线，敬请期待。")
    }
}
