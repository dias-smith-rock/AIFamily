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

    var fallbackPriceText: String {
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
    @Published private(set) var purchaseSucceeded = false

    private let storeKit = StoreKitSubscriptionService.shared

    var isLoadingProducts: Bool {
        storeKit.isLoadingProducts
    }

    func loadProducts() async {
        await storeKit.loadProducts()
        objectWillChange.send()
    }

    func displayPrice(for plan: VIPBillingPlan) -> String {
        storeKit.displayPrice(for: plan) ?? plan.fallbackPriceText
    }

    func purchaseSubscription(appRouter: AppRouter) async -> Bool {
        guard appRouter.hasPremiumAccess == false else {
            errorMessage = AppLocalized.localized("您已是 Pro 会员。")
            return false
        }
        guard isPurchasing == false else { return false }

        isPurchasing = true
        errorMessage = nil
        purchaseSucceeded = false
        defer { isPurchasing = false }

        #if canImport(Supabase)
        do {
            guard let pending = try await storeKit.purchase(plan: selectedPlan) else {
                return false
            }

            _ = try await SubscriptionSupabaseSupport.activatePremiumFromApplePurchase(
                signedTransactionInfo: pending.signedTransactionInfo,
                environment: pending.environment
            )
            await pending.finishIfNeeded()
            AnalyticsManager.log(event: .vipPurchased(plan: pending.plan.rawValue))
            await appRouter.refreshPremiumStateAfterClaim()
            purchaseSucceeded = true
            return true
        } catch let error as StoreKitSubscriptionError {
            if let message = error.errorDescription {
                errorMessage = message
            }
            return false
        } catch let error as SubscriptionSupabaseError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = AppLocalized.localized("购买失败，请稍后重试。")
            return false
        }
        #else
        errorMessage = AppLocalized.localized("当前构建环境未包含 Supabase SDK。")
        return false
        #endif
    }

    func restorePurchases(appRouter: AppRouter) async -> Bool {
        guard appRouter.hasPremiumAccess == false else { return false }
        guard isPurchasing == false else { return false }

        isPurchasing = true
        errorMessage = nil
        purchaseSucceeded = false
        defer { isPurchasing = false }

        #if canImport(Supabase)
        do {
            guard let pending = try await storeKit.restorePurchases() else {
                throw StoreKitSubscriptionError.noActiveSubscription
            }

            _ = try await SubscriptionSupabaseSupport.activatePremiumFromApplePurchase(
                signedTransactionInfo: pending.signedTransactionInfo,
                environment: pending.environment
            )
            await pending.finishIfNeeded()
            AnalyticsManager.log(event: .vipPurchased(plan: pending.plan.rawValue))
            await appRouter.refreshPremiumStateAfterClaim()
            purchaseSucceeded = true
            return true
        } catch let error as StoreKitSubscriptionError {
            errorMessage = error.errorDescription ?? AppLocalized.localized("未找到可恢复的订阅。")
            return false
        } catch let error as SubscriptionSupabaseError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = AppLocalized.localized("恢复购买失败，请稍后重试。")
            return false
        }
        #else
        errorMessage = AppLocalized.localized("当前构建环境未包含 Supabase SDK。")
        return false
        #endif
    }
}
