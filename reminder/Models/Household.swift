import Foundation

// MARK: - 1. 群组组织 (Household)
struct Household: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var avatarUrl: String?
    var description: String?
    let creatorId: UUID
    var status: HouseholdStatus
    var subscriptionPlan: SubscriptionPlan
    var subscriptionExpiresAt: Date?
    var isPremium: Bool?
    var storageUsedBytes: Int64?
    var aiQuotaUsed: Int?
    let createdAt: Date
    let updatedAt: Date
}
