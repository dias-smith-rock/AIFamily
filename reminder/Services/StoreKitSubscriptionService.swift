import Combine
import Foundation
import StoreKit

#if canImport(Supabase)
import Supabase
#endif

enum StoreKitSubscriptionError: LocalizedError {
    case productNotFound
    case userCancelled
    case pending
    case unverifiedTransaction
    case noActiveSubscription

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return L10n.Common.failedToLoadSubscriptionProductsPleaseTry.string()
        case .userCancelled:
            return nil
        case .pending:
            return L10n.Common.purchaseIsPendingCheckYourAppStoreAccount.string()
        case .unverifiedTransaction:
            return L10n.Common.purchaseVerificationFailedPleaseRetryOrCon.string()
        case .noActiveSubscription:
            return L10n.Common.noSubscriptionFoundToRestore.string()
        }
    }
}

/// 待服务端激活并 finish 的交易。
struct PendingStorePurchase: Sendable {
    let signedTransactionInfo: String
    let environment: String
    let plan: SubscriptionPlan
    let expiresAt: Date?
    private let transaction: Transaction?

    init(
        signedTransactionInfo: String,
        environment: String,
        plan: SubscriptionPlan,
        expiresAt: Date?,
        transaction: Transaction?
    ) {
        self.signedTransactionInfo = signedTransactionInfo
        self.environment = environment
        self.plan = plan
        self.expiresAt = expiresAt
        self.transaction = transaction
    }

    func finishIfNeeded() async {
        if let transaction {
            await transaction.finish()
        }
    }
}

@MainActor
final class StoreKitSubscriptionService: ObservableObject {
    static let shared = StoreKitSubscriptionService()

    @Published private(set) var productsByPlan: [VIPBillingPlan: Product] = [:]
    @Published private(set) var isLoadingProducts = false
    /// 当前 App 账号在 StoreKit 中绑定的有效订阅（`appAccountToken` 须与登录用户一致）。
    @Published private(set) var hasLocalActiveSubscription = false
    @Published private(set) var localSubscriptionExpiresAt: Date?
    /// 本机 Apple ID 有有效订阅，但未绑定到当前 App 账号（常见于切换账号后）。
    @Published private(set) var hasUnlinkedDeviceSubscription = false

    private var transactionListenerTask: Task<Void, Never>?
    private weak var appRouter: AppRouter?
    /// 本会话内服务端已确认归属当前用户的购买（沙盒常不回填 `appAccountToken`）。
    private var sessionConfirmedUserId: UUID?

    private init() {}

    func configure(appRouter: AppRouter) {
        self.appRouter = appRouter
    }

    func displayPrice(for plan: VIPBillingPlan) -> String? {
        productsByPlan[plan]?.displayPrice
    }

    func startTransactionListener() {
        guard transactionListenerTask == nil else { return }
        transactionListenerTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handleTransactionUpdate(result)
            }
        }
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: StoreKitProductCatalog.allProductIDs)
            var map: [VIPBillingPlan: Product] = [:]
            for product in products {
                if let plan = StoreKitProductCatalog.billingPlan(for: product.id) {
                    map[plan] = product
                }
            }
            productsByPlan = map
        } catch {
            productsByPlan = [:]
        }
        await refreshLocalEntitlements(for: appRouter?.authUserId)
    }

    /// 本人 VIP：云端权益，或本机 StoreKit 订阅且 `appAccountToken` 与当前用户一致。
    func isPersonalSubscriber(userEntitlement: UserEntitlement?) -> Bool {
        userEntitlement?.isActive == true || hasLocalActiveSubscription
    }

    func personalSubscriptionExpiry(userEntitlement: UserEntitlement?) -> Date? {
        if userEntitlement?.isActive == true {
            return userEntitlement?.proExpiresAt
        }
        return localSubscriptionExpiresAt
    }

    func refreshLocalEntitlements(for userId: UUID? = nil) async {
        guard let userId else {
            clearSessionSubscriptionState()
            return
        }

        var hasActiveForUser = false
        var latestExpiryForUser: Date?
        var hasAnyDeviceActive = false

        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else { continue }
            guard StoreKitProductCatalog.subscriptionPlan(for: transaction.productID) != nil else { continue }
            guard isActiveSubscription(transaction) else { continue }

            hasAnyDeviceActive = true
            guard transaction.appAccountToken == userId else { continue }

            hasActiveForUser = true
            if let expiration = transaction.expirationDate {
                if let latestExpiryForUser, expiration <= latestExpiryForUser {
                    continue
                }
                latestExpiryForUser = expiration
            }
        }

        if hasActiveForUser {
            hasLocalActiveSubscription = true
            localSubscriptionExpiresAt = latestExpiryForUser
            hasUnlinkedDeviceSubscription = false
        } else if sessionConfirmedUserId == userId {
            // 沙盒 / StoreKit 测试常延迟回填 appAccountToken；保留本会话内已确认的订阅状态。
            hasUnlinkedDeviceSubscription = hasAnyDeviceActive && !hasLocalActiveSubscription
        } else {
            hasLocalActiveSubscription = false
            localSubscriptionExpiresAt = nil
            hasUnlinkedDeviceSubscription = hasAnyDeviceActive
        }
        appRouter?.objectWillChange.send()
    }

    func clearSessionSubscriptionState() {
        sessionConfirmedUserId = nil
        hasLocalActiveSubscription = false
        localSubscriptionExpiresAt = nil
        hasUnlinkedDeviceSubscription = false
        appRouter?.objectWillChange.send()
    }

    /// 服务端已校验购买/恢复成功后，立即标记本机会话内的本人订阅（避免 UI 等待 StoreKit 回填）。
    func confirmLocalSubscription(for userId: UUID, expiresAt: Date?) {
        sessionConfirmedUserId = userId
        hasLocalActiveSubscription = true
        localSubscriptionExpiresAt = expiresAt
        hasUnlinkedDeviceSubscription = false
        appRouter?.objectWillChange.send()
    }

    func purchase(plan: VIPBillingPlan, appAccountToken: UUID) async throws -> PendingStorePurchase? {
        let product = try await resolvedProduct(for: plan)
        let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])

        switch result {
        case .success(let verification):
            return try await makePendingPurchase(from: verification, finishable: true)
        case .userCancelled:
            return nil
        case .pending:
            throw StoreKitSubscriptionError.pending
        @unknown default:
            throw StoreKitSubscriptionError.unverifiedTransaction
        }
    }

    func restorePurchases() async throws -> PendingStorePurchase? {
        try await AppStore.sync()
        let purchases = try await pendingPurchasesFromCurrentEntitlements(finishable: false)
        guard let latest = purchases.max(by: { lhs, rhs in
            expiryRank(lhs.expiresAt) < expiryRank(rhs.expiresAt)
        }) else {
            throw StoreKitSubscriptionError.noActiveSubscription
        }
        return latest
    }

    // MARK: - Transaction updates

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        #if canImport(Supabase)
        do {
            let transaction = try checkVerified(result)
            guard await shouldActivateForCurrentUser(transaction) else { return }

            guard let pending = try await makePendingPurchase(from: result, finishable: true) else {
                return
            }

            _ = try await SubscriptionSupabaseSupport.activatePremiumFromApplePurchase(
                signedTransactionInfo: pending.signedTransactionInfo,
                environment: pending.environment
            )
            await pending.finishIfNeeded()
            await appRouter?.refreshPremiumStateAfterClaim()
            AnalyticsManager.log(event: .vipPurchased(plan: pending.plan.rawValue))
        } catch {
            #if DEBUG
            print("[StoreKit] transaction update error: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    // MARK: - Helpers

    private func resolvedProduct(for plan: VIPBillingPlan) async throws -> Product {
        if let product = productsByPlan[plan] {
            return product
        }
        let products = try await Product.products(for: [StoreKitProductCatalog.productID(for: plan)])
        guard let product = products.first else {
            throw StoreKitSubscriptionError.productNotFound
        }
        productsByPlan[plan] = product
        return product
    }

    private func pendingPurchasesFromCurrentEntitlements(finishable: Bool) async throws -> [PendingStorePurchase] {
        var results: [PendingStorePurchase] = []
        for await verification in Transaction.currentEntitlements {
            if let pending = try await makePendingPurchase(from: verification, finishable: finishable) {
                results.append(pending)
            }
        }
        return results
    }

    private func makePendingPurchase(
        from verification: VerificationResult<Transaction>,
        finishable: Bool
    ) async throws -> PendingStorePurchase? {
        let transaction = try checkVerified(verification)
        guard let plan = StoreKitProductCatalog.subscriptionPlan(for: transaction.productID) else {
            if finishable {
                await transaction.finish()
            }
            return nil
        }
        guard isActiveSubscription(transaction) else {
            return nil
        }

        return PendingStorePurchase(
            signedTransactionInfo: verification.jwsRepresentation,
            environment: environmentLabel(for: transaction),
            plan: plan,
            expiresAt: transaction.expirationDate,
            transaction: finishable ? transaction : nil
        )
    }

    private func isActiveSubscription(_ transaction: Transaction) -> Bool {
        guard StoreKitProductCatalog.subscriptionPlan(for: transaction.productID) != nil else {
            return false
        }
        if let expiration = transaction.expirationDate {
            return expiration > Date()
        }
        return true
    }

    private func environmentLabel(for transaction: Transaction) -> String {
        switch transaction.environment {
        case .sandbox:
            return "sandbox"
        case .production:
            return "production"
        case .xcode:
            return "xcode"
        default:
            return "sandbox"
        }
    }

    private func expiryRank(_ date: Date?) -> TimeInterval {
        date?.timeIntervalSince1970 ?? .greatestFiniteMagnitude
    }

    private func shouldActivateForCurrentUser(_ transaction: Transaction) async -> Bool {
        #if canImport(Supabase)
        guard let currentUserId = try? await SupabaseManager.shared.client.auth.session.user.id else {
            return false
        }
        guard let token = transaction.appAccountToken else {
            return false
        }
        return token == currentUserId
        #else
        return false
        #endif
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitSubscriptionError.unverifiedTransaction
        case .verified(let safe):
            return safe
        }
    }
}
