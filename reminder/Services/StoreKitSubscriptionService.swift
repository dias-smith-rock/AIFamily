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

/// 待 finish 的交易（Supabase 回写成功后再调用 `finish()`）。
struct PendingStorePurchase: Sendable {
    let verified: VerifiedApplePurchase
    private let transaction: Transaction

    init(verified: VerifiedApplePurchase, transaction: Transaction) {
        self.verified = verified
        self.transaction = transaction
    }

    func finish() async {
        await transaction.finish()
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
            let transaction = try checkVerified(verification)
            let verified = makeVerifiedPurchase(from: transaction, product: product)
            return PendingStorePurchase(verified: verified, transaction: transaction)
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
        let purchases = try await pendingPurchasesFromCurrentEntitlements()
        guard let latest = purchases.max(by: { lhs, rhs in
            (lhs.verified.expiresAt ?? .distantFuture) < (rhs.verified.expiresAt ?? .distantFuture)
        }) else {
            throw StoreKitSubscriptionError.noActiveSubscription
        }
        return latest
    }

    func syncEntitlementsOnLaunch() async {
        #if canImport(Supabase)
        guard let appRouter else { return }
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let purchases = try await verifiedPurchasesFromCurrentEntitlements()
            guard let latest = purchases.max(by: { lhs, rhs in
                (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
            }) else { return }

            try await SubscriptionSupabaseSupport.activatePremiumFromApplePurchase(
                userId: session.user.id,
                purchase: latest
            )
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
            let transaction = try checkVerified(result)
            guard let plan = StoreKitProductCatalog.subscriptionPlan(for: transaction.productID) else {
                await transaction.finish()
                return
            }

            let product = productsByPlan.values.first { $0.id == transaction.productID }
            let verified = makeVerifiedPurchase(from: transaction, product: product)
            let userId = try await SupabaseManager.shared.client.auth.session.user.id

            try await SubscriptionSupabaseSupport.activatePremiumFromApplePurchase(
                userId: userId,
                purchase: verified
            )
            await transaction.finish()
            await appRouter?.refreshPremiumStateAfterClaim()
            AnalyticsManager.log(event: .vipPurchased(plan: plan.rawValue))
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

    private func pendingPurchasesFromCurrentEntitlements() async throws -> [PendingStorePurchase] {
        var results: [PendingStorePurchase] = []
        for await verification in Transaction.currentEntitlements {
            let transaction = try checkVerified(verification)
            guard isActiveSubscription(transaction) else { continue }
            let product = productsByPlan.values.first { $0.id == transaction.productID }
            let verified = makeVerifiedPurchase(from: transaction, product: product)
            results.append(PendingStorePurchase(verified: verified, transaction: transaction))
        }
        return results
    }

    private func verifiedPurchasesFromCurrentEntitlements() async throws -> [VerifiedApplePurchase] {
        try await pendingPurchasesFromCurrentEntitlements().map(\.verified)
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

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitSubscriptionError.unverifiedTransaction
        case .verified(let safe):
            return safe
        }
    }

    private func makeVerifiedPurchase(from transaction: Transaction, product: Product?) -> VerifiedApplePurchase {
        let plan = StoreKitProductCatalog.subscriptionPlan(for: transaction.productID) ?? .proMonthly
        let environment: String
        switch transaction.environment {
        case .sandbox:
            environment = "sandbox"
        case .production:
            environment = "production"
        default:
            environment = "production"
        }

        let amount: Int
        let currency: String
        if let product {
            amount = priceInMinorUnits(product)
            currency = "USD"
        } else {
            amount = 0
            currency = "USD"
        }

        return VerifiedApplePurchase(
            transactionId: String(transaction.id),
            productId: transaction.productID,
            plan: plan,
            expiresAt: transaction.expirationDate,
            purchaseDate: transaction.purchaseDate,
            environment: environment,
            amount: amount,
            currency: currency
        )
    }

    private func priceInMinorUnits(_ product: Product) -> Int {
        let decimal = product.price as NSDecimalNumber
        return decimal.multiplying(by: 100).intValue
    }
}
