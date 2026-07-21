import Foundation

struct LedgerTransactionDraft: Equatable, Sendable {
    var householdId: UUID
    var type: LedgerEntryType
    var amount: Double
    var currency: String
    var transactionTime: Date
    var category: ExpenseCategory
    var selectedTags: [CategoryTag]
    var payerIds: [UUID]
    var targetMemberIds: [UUID]
    var visibleMemberIds: [UUID]
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

struct LedgerTransactionUpdatePatch: Encodable {
    let type: LedgerEntryType
    let amount: Double
    let currency: String
    let transactionTime: Date
    let categoryId: UUID
    let categoryNameSnapshot: String
    let categoryIconSnapshot: String?
    let payerIds: [UUID]
    let targetMemberIds: [UUID]
    let visibleMemberIds: [UUID]
    let note: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case type
        case amount
        case currency
        case transactionTime = "transaction_time"
        case categoryId = "category_id"
        case categoryNameSnapshot = "category_name_snapshot"
        case categoryIconSnapshot = "category_icon_snapshot"
        case payerIds = "payer_ids"
        case targetMemberIds = "target_member_ids"
        case visibleMemberIds = "visible_member_ids"
        case note
        case updatedAt = "updated_at"
    }
}
