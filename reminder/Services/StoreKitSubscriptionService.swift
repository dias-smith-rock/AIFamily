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
            return String(localized: "订阅商品加载失败，请稍后重试。")
        case .userCancelled:
            return nil
        case .pending:
            return String(localized: "购买正在处理中，请稍后在 App Store 账户中查看。")
        case .unverifiedTransaction:
            return String(localized: "购买验证失败，请重试或联系支持。")
        case .noActiveSubscription:
            return String(localized: "未找到可恢复的订阅。")
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

    private var transactionListenerTask: Task<Void, Never>?
    private weak var appRouter: AppRouter?

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
    }

    func purchase(plan: VIPBillingPlan) async throws -> PendingStorePurchase? {
        let product = try await resolvedProduct(for: plan)
        let result = try await product.purchase()

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

    func syncEntitlementsOnLaunch() async {
        #if canImport(Supabase)
        guard let appRouter else { return }
        do {
            let purchases = try await pendingPurchasesFromCurrentEntitlements(finishable: false)
            guard let latest = purchases.max(by: { lhs, rhs in
                expiryRank(lhs.expiresAt) < expiryRank(rhs.expiresAt)
            }) else { return }

            _ = try await SubscriptionSupabaseSupport.activatePremiumFromApplePurchase(
                signedTransactionInfo: latest.signedTransactionInfo,
                environment: latest.environment
            )
            await latest.finishIfNeeded()
            await appRouter.refreshPremiumStateAfterClaim()
        } catch {
            #if DEBUG
            print("[StoreKit] syncEntitlementsOnLaunch error: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    // MARK: - Transaction updates

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        #if canImport(Supabase)
        do {
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
        default:
            return "production"
        }
    }

    private func expiryRank(_ date: Date?) -> TimeInterval {
        date?.timeIntervalSince1970 ?? .greatestFiniteMagnitude
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
