import Foundation

struct LedgerTransactionDraft: Equatable, Sendable {
    var householdId: UUID
    var type: LedgerEntryType
    var amount: Double
    var currency: String
    var transactionTime: Date
    var category: ExpenseCategory
    var selectedTags: [CategoryTag]
    var payerId: UUID?
    var targetMemberIds: [UUID]
    var note: String?
    var creatorProfileId: UUID
}

struct CategorySoftDeletePatch: Encodable {
    let isDeleted: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case isDeleted = "is_deleted"
        case updatedAt = "updated_at"
    }
}

struct CategoryUpdatePatch: Encodable {
    let name: String
    let icon: String
    let colorHex: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name
        case icon
        case colorHex = "color_hex"
        case updatedAt = "updated_at"
    }
}

struct TagSoftDeletePatch: Encodable {
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case isDeleted = "is_deleted"
    }
}
