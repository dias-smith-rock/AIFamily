import Foundation

/// App Store Connect 订阅 Product ID 与业务方案映射。
enum StoreKitProductCatalog {
    static let monthlyProductID = "wesync.vip.monthly"
    static let yearlyProductID = "wesync.vip.yearly"

    static var allProductIDs: [String] {
        [monthlyProductID, yearlyProductID]
    }

    static func billingPlan(for productID: String) -> VIPBillingPlan? {
        switch productID {
        case monthlyProductID: .monthly
        case yearlyProductID: .yearly
        default: nil
        }
    }

    static func subscriptionPlan(for productID: String) -> SubscriptionPlan? {
        billingPlan(for: productID)?.subscriptionPlan
    }

    static func productID(for plan: VIPBillingPlan) -> String {
        switch plan {
        case .monthly: monthlyProductID
        case .yearly: yearlyProductID
        }
    }
}
