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
        case .monthly: L10n.Common.monthly2.localized
        case .yearly: L10n.Common.yearly2.localized
        }
    }

    var planTitle: LocalizedStringKey {
        switch self {
        case .monthly: L10n.Common.monthly.localized
        case .yearly: L10n.Common.yearly.localized
        }
    }

    var isRecommended: Bool {
        self == .yearly
    }

    var savingsBadge: LocalizedStringKey? {
        isRecommended ? L10n.Common.save33.localized : nil
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
        guard storeKit.isPersonalSubscriber(userEntitlement: appRouter.userEntitlement) == false else {
            errorMessage = AppLocalized.localized(L10n.VIP.youAlreadyHaveProMembership)
            return false
        }
        guard isPurchasing == false else { return false }

        isPurchasing = true
        errorMessage = nil
        purchaseSucceeded = false
        defer { isPurchasing = false }

        #if canImport(Supabase)
        do {
            let userId = await appRouter.resolveAuthUserId()
            guard let pending = try await storeKit.purchase(plan: selectedPlan, appAccountToken: userId) else {
                return false
            }

            storeKit.confirmLocalSubscription(for: userId, expiresAt: pending.expiresAt)
            await storeKit.refreshLocalEntitlements(for: userId)

            if let userId {
                let response = try await SubscriptionSupabaseSupport.activatePremiumFromApplePurchase(
                    signedTransactionInfo: pending.signedTransactionInfo,
                    environment: pending.environment
                )
                let expiresAt = Self.parseSubscriptionExpiry(
                    serverExpiresAt: response.expiresAt,
                    fallback: pending.expiresAt
                )
                appRouter.applyOptimisticPersonalEntitlement(userId: userId, expiresAt: expiresAt)
                await pending.finishIfNeeded()
                AnalyticsManager.log(event: .vipPurchased(plan: pending.plan.rawValue))
                await appRouter.refreshPremiumStateAfterClaim()
            } else {
                await pending.finishIfNeeded()
                AnalyticsManager.log(event: .vipPurchased(plan: pending.plan.rawValue))
            }

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
            errorMessage = AppLocalized.localized(L10n.Common.purchaseFailedPleaseTryAgainLater)
            return false
        }
        #else
        errorMessage = AppLocalized.localized(L10n.Common.supabaseSdkIsNotAvailableInThisBuild)
        return false
        #endif
    }

    func restorePurchases(appRouter: AppRouter) async -> Bool {
        guard storeKit.isPersonalSubscriber(userEntitlement: appRouter.userEntitlement) == false else {
            return false
        }
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

            let userId = await appRouter.resolveAuthUserId()
            storeKit.confirmLocalSubscription(for: userId, expiresAt: pending.expiresAt)
            await storeKit.refreshLocalEntitlements(for: userId ?? appRouter.authUserId)

            if let userId {
                let response = try await SubscriptionSupabaseSupport.activatePremiumFromApplePurchase(
                    signedTransactionInfo: pending.signedTransactionInfo,
                    environment: pending.environment
                )
                let expiresAt = Self.parseSubscriptionExpiry(
                    serverExpiresAt: response.expiresAt,
                    fallback: pending.expiresAt
                )
                appRouter.applyOptimisticPersonalEntitlement(userId: userId, expiresAt: expiresAt)
                await pending.finishIfNeeded()
                AnalyticsManager.log(event: .vipPurchased(plan: pending.plan.rawValue))
                await appRouter.refreshPremiumStateAfterClaim()
            } else {
                await pending.finishIfNeeded()
                AnalyticsManager.log(event: .vipPurchased(plan: pending.plan.rawValue))
            }

            purchaseSucceeded = true
            return true
        } catch let error as StoreKitSubscriptionError {
            errorMessage = error.errorDescription ?? AppLocalized.localized(L10n.VIP.noSubscriptionFoundToRestore)
            return false
        } catch let error as SubscriptionSupabaseError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = AppLocalized.localized(L10n.Common.restoreFailedPleaseTryAgainLater)
            return false
        }
        #else
        errorMessage = AppLocalized.localized(L10n.Common.supabaseSdkIsNotAvailableInThisBuild)
        return false
        #endif
    }

    private static func parseSubscriptionExpiry(serverExpiresAt: String?, fallback: Date?) -> Date? {
        if let serverExpiresAt,
           serverExpiresAt.isEmpty == false,
           let parsed = ISO8601DateFormatter().date(from: serverExpiresAt) {
            return parsed
        }
        if let serverExpiresAt,
           serverExpiresAt.isEmpty == false {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: serverExpiresAt) {
                return parsed
            }
        }
        return fallback
    }
}
