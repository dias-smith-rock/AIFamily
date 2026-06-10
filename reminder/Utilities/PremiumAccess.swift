import Foundation

/// VIP 权限网关：个人 Pro 有效，或当前组织创建者 Pro 有效（组织内继承）。
enum PremiumAccess {
    /// R1：本人 VIP → 所有组织；R2/R3：仅当当前组织创建者为 VIP 时继承。
    static func hasPremiumAccess(
        userEntitlement: UserEntitlement?,
        creatorHasActivePro: Bool
    ) -> Bool {
        if userEntitlement?.isActive == true {
            return true
        }
        return creatorHasActivePro
    }

    /// 仅通过组织创建者继承（非个人 VIP）。
    static func hasInheritedPremiumOnly(
        userEntitlement: UserEntitlement?,
        creatorHasActivePro: Bool
    ) -> Bool {
        creatorHasActivePro && userEntitlement?.isActive != true
    }
}
