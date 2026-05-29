import Foundation

// MARK: - 订阅订单 (SubscriptionOrder)

struct SubscriptionOrder: Identifiable, Codable, Equatable {
    let id: UUID
    let payerId: UUID
    let planPurchased: SubscriptionPlan
    let amount: Int
    let currency: String
    let paymentMethod: PaymentMethod
    let externalTransactionId: String?
    var status: OrderStatus
    var paidAt: Date?
    var expiresAt: Date?
    var environment: String?
    let createdAt: Date
    let updatedAt: Date
}

/// 写入 `subscription_orders`（不含 `household_id`）。
struct SubscriptionOrderInsertPayload: Encodable, Equatable, Sendable {
    var payerId: UUID
    var planPurchased: String
    var amount: Int
    var currency: String
    var paymentMethod: String
    var status: String
    var environment: String
    var expiresAt: Date?
    var paidAt: Date?

    init(
        payerId: UUID,
        planPurchased: String,
        amount: Int = 0,
        currency: String = "USD",
        paymentMethod: String = PaymentMethod.appleIAP.rawValue,
        status: String = OrderStatus.completed.rawValue,
        environment: String = "production",
        expiresAt: Date? = nil,
        paidAt: Date? = Date()
    ) {
        self.payerId = payerId
        self.planPurchased = planPurchased
        self.amount = amount
        self.currency = currency
        self.paymentMethod = paymentMethod
        self.status = status
        self.environment = environment
        self.expiresAt = expiresAt
        self.paidAt = paidAt
    }
}
