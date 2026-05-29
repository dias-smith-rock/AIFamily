import Foundation

/// `user_entitlements` 表：VIP 权益跟随个人账号。
struct UserEntitlement: Identifiable, Codable, Equatable, Sendable {
    var userId: UUID
    var isPro: Bool
    var proExpiresAt: Date?

    var id: UUID { userId }

    init(userId: UUID, isPro: Bool, proExpiresAt: Date? = nil) {
        self.userId = userId
        self.isPro = isPro
        self.proExpiresAt = proExpiresAt
    }

    /// 权益是否在有效期内（`isPro` 为真且未过期）。
    var isActive: Bool {
        guard isPro else { return false }
        guard let proExpiresAt else { return true }
        return proExpiresAt > Date()
    }
}
