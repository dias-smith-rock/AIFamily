import Foundation

/// StoreKit 2 验签通过后的购买快照，用于回写 Supabase。
struct VerifiedApplePurchase: Sendable, Equatable {
    let transactionId: String
    let productId: String
    let plan: SubscriptionPlan
    let expiresAt: Date?
    let purchaseDate: Date
    let environment: String
    let amount: Int
    let currency: String
}
