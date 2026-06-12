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

    private let revenueCat = RevenueCatSubscriptionService.shared

    var isLoadingProducts: Bool {
        revenueCat.isLoadingProducts
    }

    var canPurchaseSelectedPlan: Bool {
        revenueCat.canPurchase(plan: selectedPlan)
    }

    func loadProducts() async {
        await revenueCat.loadOfferings()
        objectWillChange.send()
    }

    func displayPrice(for plan: VIPBillingPlan) -> String {
        revenueCat.displayPrice(for: plan) ?? plan.fallbackPriceText
    }

    func purchaseSubscription(appRouter: AppRouter) async -> Bool {
        guard revenueCat.isPersonalSubscriber(userEntitlement: appRouter.userEntitlement) == false else {
            errorMessage = AppLocalized.localized(L10n.VIP.youAlreadyHaveProMembership)
            return false
        }
        guard isPurchasing == false else { return false }

        isPurchasing = true
        errorMessage = nil
        purchaseSucceeded = false
        defer { isPurchasing = false }

        do {
            if let userId = await appRouter.resolveAuthUserId() {
                await revenueCat.alignLoggedInRevenueCatUser(supabaseUserId: userId)
            }

            let purchased = try await revenueCat.purchase(plan: selectedPlan)
            guard purchased else { return false }

            if let userId = await appRouter.resolveAuthUserId() {
                appRouter.applyOptimisticPersonalEntitlement(
                    userId: userId,
                    expiresAt: revenueCat.proExpiresAt
                )
                await revenueCat.syncEntitlementToCloudIfNeeded(appRouter: appRouter)
            }

            purchaseSucceeded = true
            return true
        } catch let error as RevenueCatSubscriptionError {
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
    }

    func restorePurchases(appRouter: AppRouter) async -> Bool {
        guard revenueCat.isPersonalSubscriber(userEntitlement: appRouter.userEntitlement) == false else {
            return false
        }
        guard isPurchasing == false else { return false }

        isPurchasing = true
        errorMessage = nil
        purchaseSucceeded = false
        defer { isPurchasing = false }

        do {
            if let userId = await appRouter.resolveAuthUserId() {
                await revenueCat.alignLoggedInRevenueCatUser(supabaseUserId: userId)
            }

            let restored = try await revenueCat.restorePurchases()
            guard restored else { return false }

            if let userId = await appRouter.resolveAuthUserId() {
                appRouter.applyOptimisticPersonalEntitlement(
                    userId: userId,
                    expiresAt: revenueCat.proExpiresAt
                )
                await revenueCat.syncEntitlementToCloudIfNeeded(appRouter: appRouter)
            }

            purchaseSucceeded = true
            return true
        } catch let error as RevenueCatSubscriptionError {
            errorMessage = error.errorDescription ?? AppLocalized.localized(L10n.VIP.noSubscriptionFoundToRestore)
            return false
        } catch let error as SubscriptionSupabaseError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = AppLocalized.localized(L10n.Common.restoreFailedPleaseTryAgainLater)
            return false
        }
    }
}
