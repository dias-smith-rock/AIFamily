import Combine
import Foundation
import RevenueCat

#if canImport(Supabase)
import Supabase
#endif

enum RevenueCatSubscriptionError: LocalizedError {
    case notConfigured
    case productNotFound
    case userCancelled
    case pending
    case noActiveSubscription

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return AppLocalized.localizedSync(L10n.VIP.failedToLoadSubscriptionProductsPleaseTry)
        case .productNotFound:
            return AppLocalized.localizedSync(L10n.VIP.failedToLoadSubscriptionProductsPleaseTry)
        case .userCancelled:
            return nil
        case .pending:
            return AppLocalized.localizedSync(L10n.Common.purchaseIsPendingCheckYourAppStoreAccount)
        case .noActiveSubscription:
            return AppLocalized.localizedSync(L10n.VIP.noSubscriptionFoundToRestore)
        }
    }
}

@MainActor
final class RevenueCatSubscriptionService: NSObject, ObservableObject {
    static let shared = RevenueCatSubscriptionService()

    @Published private(set) var packagesByPlan: [VIPBillingPlan: Package] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var hasActiveProEntitlement = false
    @Published private(set) var proExpiresAt: Date?
    @Published private(set) var isConfigured = false

    private weak var appRouter: AppRouter?
    private var customerInfo: CustomerInfo?

    private override init() {
        super.init()
    }

    func configure(appRouter: AppRouter) {
        self.appRouter = appRouter
        guard isConfigured == false else { return }
        guard let apiKey = RevenueCatConfiguration.publicAPIKey else {
            #if DEBUG
            print("[RevenueCat] missing RevenueCatAPIKey in Info.plist")
            #endif
            return
        }

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = self
        isConfigured = true

        Task {
            await refreshCustomerInfo()
        }
    }

    func displayPrice(for plan: VIPBillingPlan) -> String? {
        packagesByPlan[plan]?.localizedPriceString
    }

    func isPersonalSubscriber(userEntitlement: UserEntitlement?) -> Bool {
        userEntitlement?.isActive == true || hasActiveProEntitlement
    }

    func personalSubscriptionExpiry(userEntitlement: UserEntitlement?) -> Date? {
        if userEntitlement?.isActive == true {
            return userEntitlement?.proExpiresAt
        }
        return proExpiresAt
    }

    func loadOfferings() async {
        guard isConfigured else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let offerings = try await Purchases.shared.offerings()
            var map: [VIPBillingPlan: Package] = [:]
            let packages = offerings.current?.availablePackages ?? []
            for package in packages {
                let productId = package.storeProduct.productIdentifier
                if let plan = StoreKitProductCatalog.billingPlan(for: productId) {
                    map[plan] = package
                }
            }
            packagesByPlan = map
        } catch {
            packagesByPlan = [:]
            #if DEBUG
            print("[RevenueCat] loadOfferings error: \(error.localizedDescription)")
            #endif
        }
        await refreshCustomerInfo()
    }

    func refreshCustomerInfo() async {
        guard isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            applyCustomerInfo(info)
        } catch {
            #if DEBUG
            print("[RevenueCat] customerInfo error: \(error.localizedDescription)")
            #endif
        }
    }

    func logIn(userId: UUID) async {
        guard isConfigured else { return }
        do {
            let result = try await Purchases.shared.logIn(userId.uuidString.lowercased())
            applyCustomerInfo(result.customerInfo)
        } catch {
            #if DEBUG
            print("[RevenueCat] logIn error: \(error.localizedDescription)")
            #endif
        }
    }

    func logOut() async {
        guard isConfigured else { return }
        do {
            let info = try await Purchases.shared.logOut()
            applyCustomerInfo(info)
        } catch {
            hasActiveProEntitlement = false
            proExpiresAt = nil
            customerInfo = nil
            #if DEBUG
            print("[RevenueCat] logOut error: \(error.localizedDescription)")
            #endif
        }
    }

    func purchase(plan: VIPBillingPlan) async throws -> Bool {
        guard isConfigured else { throw RevenueCatSubscriptionError.notConfigured }
        let package: Package
        if let cached = packagesByPlan[plan] {
            package = cached
        } else if let resolved = await resolvePackage(for: plan) {
            package = resolved
        } else {
            throw RevenueCatSubscriptionError.productNotFound
        }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                return false
            }
            applyCustomerInfo(result.customerInfo)
            if let entitlement = result.customerInfo.entitlements[RevenueCatConfiguration.premiumEntitlementID],
               entitlement.isActive {
                AnalyticsManager.log(event: .vipPurchased(plan: plan.subscriptionPlan.rawValue))
                return true
            }
            return false
        } catch let error as RevenueCat.ErrorCode {
            if error == .purchaseCancelledError {
                return false
            }
            if error == .paymentPendingError {
                throw RevenueCatSubscriptionError.pending
            }
            throw error
        }
    }

    func restorePurchases() async throws -> Bool {
        guard isConfigured else { throw RevenueCatSubscriptionError.notConfigured }
        let info = try await Purchases.shared.restorePurchases()
        applyCustomerInfo(info)
        guard hasActiveProEntitlement else {
            throw RevenueCatSubscriptionError.noActiveSubscription
        }
        return true
    }

    /// 已登录用户：将 RevenueCat 真相同步至 Supabase `user_entitlements`（兜底）。
    func syncEntitlementToCloudIfNeeded(appRouter: AppRouter) async {
        #if canImport(Supabase)
        guard isConfigured else { return }
        guard await appRouter.resolveAuthUserId() != nil else { return }

        do {
            _ = try await SubscriptionSupabaseSupport.syncEntitlementFromRevenueCat()
            await appRouter.refreshPremiumStateAfterClaim()
        } catch {
            #if DEBUG
            print("[RevenueCat] syncEntitlementToCloud error: \(error.localizedDescription)")
            #endif
        }
        #else
        _ = appRouter
        #endif
    }

    private func resolvePackage(for plan: VIPBillingPlan) async -> Package? {
        await loadOfferings()
        return packagesByPlan[plan]
    }

    private func applyCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        let entitlement = info.entitlements[RevenueCatConfiguration.premiumEntitlementID]
        hasActiveProEntitlement = entitlement?.isActive == true
        proExpiresAt = entitlement?.expirationDate
        appRouter?.objectWillChange.send()
    }
}

extension RevenueCatSubscriptionService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.applyCustomerInfo(customerInfo)
        }
    }
}
