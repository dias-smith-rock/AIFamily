import Foundation

/// VIP 权限网关：个人 Pro 权益有效，或当前群组已继承 Premium 状态。
enum PremiumAccess {
    static func hasPremiumAccess(
        userEntitlement: UserEntitlement?,
        householdIsPremium: Bool
    ) -> Bool {
        if householdIsPremium {
            return true
        }
        return userEntitlement?.isActive == true
    }
}
