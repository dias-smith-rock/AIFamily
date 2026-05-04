import Foundation

// MARK: - 3. 邀请核销凭证 (InviteLinkNonce)
struct InviteLinkNonce: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    let creatorId: UUID
    let nonce: String
    let expiresAt: Date
    var isUsed: Bool
    var usedBy: UUID?
    let createdAt: Date
}
