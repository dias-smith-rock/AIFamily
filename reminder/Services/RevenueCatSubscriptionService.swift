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
    case entitlementNotGranted

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
        case .entitlementNotGranted:
            return AppLocalized.localizedSync(L10n.Common.purchaseFailedPleaseTryAgainLater)
        }
    }
}

@MainActor
final class RevenueCatSubscriptionService: NSObject, ObservableObject {
    static let shared = RevenueCatSubscriptionService()

    @Published private(set) var packagesByPlan: [VIPBillingPlan: Package] = [:]
    @Published private(set) var storeProductsByPlan: [VIPBillingPlan: StoreProduct] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var hasActiveProEntitlement = false
    @Published private(set) var proExpiresAt: Date?
    @Published private(set) var isConfigured = false
    /// 本机 VIP 已激活但云端 `user_entitlements` 未对齐时为 true。
    @Published private(set) var showsCloudSyncWarning = false
    @Published private(set) var cloudSyncErrorMessage: String?

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
            await loadOfferings()
            await refreshCustomerInfo()
        }
    }

    func canPurchase(plan: VIPBillingPlan) -> Bool {
        packagesByPlan[plan] != nil || storeProductsByPlan[plan] != nil
    }

    func displayPrice(for plan: VIPBillingPlan) -> String? {
        packagesByPlan[plan]?.localizedPriceString
            ?? storeProductsByPlan[plan]?.localizedPriceString
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

        var packageMap: [VIPBillingPlan: Package] = [:]
        do {
            let offerings = try await Purchases.shared.offerings()
            let packages = collectPackages(from: offerings)
            packageMap = mapPackages(packages)

            #if DEBUG
            if packageMap.isEmpty {
                let productIds = packages.map(\.storeProduct.productIdentifier)
                print("[RevenueCat] offerings loaded but no plan match. current=\(offerings.current?.identifier ?? "nil") productIds=\(productIds)")
            }
            #endif
        } catch {
            #if DEBUG
            print("[RevenueCat] loadOfferings error: \(error.localizedDescription)")
            #endif
        }

        packagesByPlan = packageMap

        var productMap = packageMap.reduce(into: [VIPBillingPlan: StoreProduct]()) { partial, entry in
            partial[entry.key] = entry.value.storeProduct
        }
        let missingPlans = VIPBillingPlan.allCases.filter { productMap[$0] == nil }
        if missingPlans.isEmpty == false {
            do {
                let productIds = missingPlans.map { StoreKitProductCatalog.productID(for: $0) }
                let products = try await Purchases.shared.products(productIds)
                for product in products {
                    if let plan = StoreKitProductCatalog.billingPlan(for: product.productIdentifier) {
                        productMap[plan] = product
                    }
                }
                #if DEBUG
                if missingPlans.contains(where: { productMap[$0] == nil }) {
                    let found = products.map(\.productIdentifier)
                    print("[RevenueCat] StoreKit products fallback incomplete. requested=\(productIds) found=\(found)")
                }
                #endif
            } catch {
                #if DEBUG
                print("[RevenueCat] products fallback error: \(error.localizedDescription)")
                #endif
            }
        }
        storeProductsByPlan = productMap
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

    @discardableResult
    func logIn(userId: UUID) async -> Bool {
        guard isConfigured else { return false }
        do {
            let result = try await Purchases.shared.logIn(userId.uuidString.lowercased())
            applyCustomerInfo(result.customerInfo)
            print(
                "[RevenueCat] logIn ok created=\(result.created) " +
                "appUserID=\(Purchases.shared.appUserID)"
            )
            return true
        } catch {
            print("[RevenueCat] logIn error: \(error.localizedDescription)")
            return false
        }
    }

    /// 已登录 Supabase 用户：合并匿名购买并推送收据到 RevenueCat 云端（sync 前必须调用）。
    func alignLoggedInRevenueCatUser(supabaseUserId: UUID) async {
        guard isConfigured else { return }

        let target = supabaseUserId.uuidString.lowercased()
        let current = Purchases.shared.appUserID

        if current != target {
            _ = await logIn(userId: supabaseUserId)
        }

        if Purchases.shared.appUserID.hasPrefix("$RCAnonymousID") {
            print("[RevenueCat] still anonymous after logIn; running restorePurchases")
            _ = try? await restorePurchases()
        }

        _ = try? await Purchases.shared.syncPurchases()
        await refreshCustomerInfo()
        print(
            "[RevenueCat] align identity done appUserID=\(Purchases.shared.appUserID) " +
            "localPro=\(hasActiveProEntitlement)"
        )
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

        if packagesByPlan[plan] == nil, storeProductsByPlan[plan] == nil {
            await loadOfferings()
        }

        do {
            let result: PurchaseResultData
            if let package = packagesByPlan[plan] {
                result = try await Purchases.shared.purchase(package: package)
            } else if let product = storeProductsByPlan[plan] {
                result = try await Purchases.shared.purchase(product: product)
            } else {
                throw RevenueCatSubscriptionError.productNotFound
            }

            if result.userCancelled {
                return false
            }
            applyCustomerInfo(result.customerInfo)
            if hasActiveProEntitlement == false {
                let refreshed = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
                applyCustomerInfo(refreshed)
            }
            guard hasActiveProEntitlement else {
                #if DEBUG
                let info = customerInfo ?? result.customerInfo
                let entitlementKeys = info.entitlements.all.keys.joined(separator: ", ")
                print(
                    "[RevenueCat] purchase finished but premium inactive. " +
                    "entitlementKeys=[\(entitlementKeys)] " +
                    "activeSubscriptions=\(info.activeSubscriptions)"
                )
                #endif
                throw RevenueCatSubscriptionError.entitlementNotGranted
            }
            AnalyticsManager.log(event: .vipPurchased(plan: plan.subscriptionPlan.rawValue))
            return true
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
    @discardableResult
    func syncEntitlementToCloudIfNeeded(appRouter: AppRouter) async -> Bool {
        #if canImport(Supabase)
        guard isConfigured else { return false }
        guard let userId = await appRouter.resolveAuthUserId() else {
            clearCloudSyncWarning()
            return false
        }

        await alignLoggedInRevenueCatUser(supabaseUserId: userId)

        let maxAttempts = hasActiveProEntitlement ? 3 : 1
        var lastResponse: SyncRevenueCatEntitlementResponse?

        do {
            for attempt in 1...maxAttempts {
                let response = try await SubscriptionSupabaseSupport.syncEntitlementFromRevenueCat(
                    request: makeSyncRequestPayload()
                )
                lastResponse = response
                await appRouter.refreshPremiumStateAfterClaim()
                updateCloudSyncWarning(appRouter: appRouter, syncResponse: response)

                if showsCloudSyncWarning == false {
                    return true
                }

                if attempt < maxAttempts {
                    print(
                        "[RevenueCat] cloud sync retry \(attempt)/\(maxAttempts) " +
                        "isPro=\(response.isPro == true) diagnostics=\(response.diagnosticsSummary)"
                    )
                    try await Task.sleep(for: .seconds(2))
                    _ = try? await Purchases.shared.syncPurchases()
                    await refreshCustomerInfo()
                }
            }

            if let lastResponse {
                let alias = lastResponse.resolvedFromAppUserId ?? "nil"
                let syncSource = lastResponse.syncSource ?? "nil"
                print(
                    "[RevenueCat] cloud sync mismatch after retries. " +
                    "synced.isPro=\(lastResponse.isPro == true) syncSource=\(syncSource) " +
                    "resolvedFrom=\(alias) \(lastResponse.diagnosticsSummary)"
                )
            }
            return false
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            cloudSyncErrorMessage = message
            showsCloudSyncWarning = hasActiveProEntitlement
            print("[RevenueCat] syncEntitlementToCloud error: \(message)")
            return false
        }
        #else
        _ = appRouter
        return false
        #endif
    }

    private func clearCloudSyncWarning() {
        showsCloudSyncWarning = false
        cloudSyncErrorMessage = nil
    }

    private func updateCloudSyncWarning(
        appRouter: AppRouter,
        syncResponse: SyncRevenueCatEntitlementResponse
    ) {
        let localActive = hasActiveProEntitlement
        let cloudActive = appRouter.userEntitlement?.isActive == true
        let syncedPro = syncResponse.isPro == true

        if localActive && cloudActive == false {
            if syncedPro {
                clearCloudSyncWarning()
                return
            }
            showsCloudSyncWarning = true
            cloudSyncErrorMessage = AppLocalized.localizedSync(L10n.VIP.cloudSyncFailedTapRetry)
            let syncSource = syncResponse.syncSource ?? "nil"
            print(
                "[RevenueCat] cloud sync mismatch: local VIP active, cloud inactive. " +
                "synced.isPro=\(syncedPro) syncSource=\(syncSource) \(syncResponse.diagnosticsSummary)"
            )
            return
        }

        clearCloudSyncWarning()
    }

    private func collectPackages(from offerings: Offerings) -> [Package] {
        if let current = offerings.current {
            return current.availablePackages
        }
        if let named = offerings.offering(identifier: RevenueCatConfiguration.defaultOfferingIdentifier) {
            return named.availablePackages
        }
        if let legacy = offerings.offering(identifier: RevenueCatConfiguration.legacyOfferingIdentifier) {
            return legacy.availablePackages
        }
        return offerings.all.values.flatMap(\.availablePackages)
    }

    private func mapPackages(_ packages: [Package]) -> [VIPBillingPlan: Package] {
        var map: [VIPBillingPlan: Package] = [:]
        for package in packages {
            let productId = package.storeProduct.productIdentifier
            if let plan = StoreKitProductCatalog.billingPlan(for: productId) {
                map[plan] = package
                continue
            }
            if let plan = billingPlan(for: package.packageType), map[plan] == nil {
                map[plan] = package
            }
        }
        return map
    }

    private func billingPlan(for packageType: PackageType) -> VIPBillingPlan? {
        switch packageType {
        case .monthly: .monthly
        case .annual: .yearly
        default: nil
        }
    }

    private func applyCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        let premium = resolvePremiumState(from: info)
        hasActiveProEntitlement = premium.isActive
        proExpiresAt = premium.expiresAt
        appRouter?.objectWillChange.send()
    }

    private func makeSyncRequestPayload() -> SyncRevenueCatEntitlementRequest {
        var aliasIds: [String] = []
        let currentAppUserId = Purchases.shared.appUserID
        if let info = customerInfo {
            let original = info.originalAppUserId
            if original.isEmpty == false, original != currentAppUserId {
                aliasIds.append(original)
            }
        }

        var localHint: SyncRevenueCatLocalEntitlementHint?
        if hasActiveProEntitlement, let info = customerInfo {
            let activeProductId = resolveActiveProductId(from: info)
            localHint = SyncRevenueCatLocalEntitlementHint(
                isPro: true,
                proExpiresAt: proExpiresAt.map { ISO8601DateFormatter().string(from: $0) },
                productId: activeProductId
            )
            #if DEBUG
            print(
                "[RevenueCat] sync payload aliases=\(aliasIds) " +
                "productId=\(activeProductId ?? "nil") expires=\(localHint?.proExpiresAt ?? "nil")"
            )
            #endif
        }

        return SyncRevenueCatEntitlementRequest(
            aliasAppUserIds: aliasIds.isEmpty ? nil : aliasIds,
            localEntitlement: localHint
        )
    }

    private func resolveActiveProductId(from info: CustomerInfo) -> String? {
        for productId in StoreKitProductCatalog.allProductIDs where info.activeSubscriptions.contains(productId) {
            return productId
        }
        if let premium = info.entitlements[RevenueCatConfiguration.premiumEntitlementID],
           premium.isActive {
            let productId = premium.productIdentifier
            if StoreKitProductCatalog.allProductIDs.contains(productId) {
                return productId
            }
        }
        for productId in StoreKitProductCatalog.allProductIDs {
            if let entitlement = info.entitlements[productId], entitlement.isActive {
                return productId
            }
        }
        return nil
    }

    private func resolvePremiumState(from info: CustomerInfo) -> (isActive: Bool, expiresAt: Date?) {
        if let entitlement = info.entitlements[RevenueCatConfiguration.premiumEntitlementID],
           entitlement.isActive {
            return (true, entitlement.expirationDate)
        }
        for productId in StoreKitProductCatalog.allProductIDs where info.activeSubscriptions.contains(productId) {
            return (true, info.expirationDate(forProductIdentifier: productId))
        }
        return (false, nil)
    }
}

private extension SyncRevenueCatEntitlementResponse {
    var diagnosticsSummary: String {
        guard let diagnostics else { return "diagnostics=nil" }
        let entitlements = diagnostics.entitlementKeys?.joined(separator: ",") ?? "[]"
        let subscriptions = diagnostics.subscriptionKeys?.joined(separator: ",") ?? "[]"
        return (
            "entitlements=[\(entitlements)] subscriptions=[\(subscriptions)] " +
            "originalAppUserId=\(diagnostics.originalAppUserId ?? "nil") " +
            "resolvedFrom=\(diagnostics.resolvedFrom ?? "nil")"
        )
    }
}

extension RevenueCatSubscriptionService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.applyCustomerInfo(customerInfo)
        }
    }
}
