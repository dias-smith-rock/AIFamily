import Foundation

struct PointsLedgerEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let householdId: UUID
    let targetProfileId: UUID
    let amount: Int
    let description: String
    let createdAt: Date
}
