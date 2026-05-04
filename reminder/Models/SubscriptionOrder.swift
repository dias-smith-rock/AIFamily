import Foundation

// MARK: - 6. 订阅订单 (SubscriptionOrder)
struct SubscriptionOrder: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    let payerId: UUID
    let planPurchased: SubscriptionPlan
    let amount: Int
    let currency: String
    let paymentMethod: PaymentMethod
    let externalTransactionId: String?
    var status: OrderStatus
    var paidAt: Date?

    let createdAt: Date
    let updatedAt: Date
}
