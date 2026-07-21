import Foundation

enum LedgerEntryType: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
}

struct ExpenseCategory: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let householdId: UUID
    var type: LedgerEntryType
    var name: String
    var presetKey: String?
    var icon: String
    var colorHex: String?
    var isPreset: Bool
    var sortOrder: Int
    var isDeleted: Bool
    let createdAt: Date
    var updatedAt: Date

    var displayLabel: String {
        "\(icon) \(name)"
    }
}

struct CategoryTag: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let categoryId: UUID
    let householdId: UUID
    var name: String
    var presetKey: String?
    var isPreset: Bool
    var isDeleted: Bool
    let createdAt: Date
}

struct LedgerTransaction: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let householdId: UUID
    let creatorId: UUID
    var type: LedgerEntryType
    var amount: Double
    var currency: String
    var transactionTime: Date
    var categoryId: UUID?
    var categoryNameSnapshot: String
    var categoryIconSnapshot: String?
    /// `ledger_transactions.payer_ids` — 垫付人 **family_profiles.id[]**。
    var payerIds: [UUID]
    var targetMemberIds: [UUID]
    /// `ledger_transactions.visible_member_ids` — 可见成员 **family_profiles.id[]**；空 = 不额外限制。
    var visibleMemberIds: [UUID]
    var note: String?
    var attachmentUrls: [String]
    var source: String
    let createdAt: Date
    var updatedAt: Date

    /// 列表展示用的标签快照（非库表列，由客户端组装）。
    var tagSnapshots: [String] = []

    /// 兼容旧单垫付人调用；权威字段为 `payerIds`。
    var payerId: UUID? { payerIds.first }

    /// 与 RLS 一致：空列表不额外限制；否则需在列表内或为记账人。
    func isVisible(to viewerProfileId: UUID?) -> Bool {
        if visibleMemberIds.isEmpty { return true }
        guard let viewerProfileId else { return false }
        return visibleMemberIds.contains(viewerProfileId) || creatorId == viewerProfileId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case householdId
        case creatorId
        case type
        case amount
        case currency
        case transactionTime
        case categoryId
        case categoryNameSnapshot
        case categoryIconSnapshot
        case payerIds
        case payerId
        case targetMemberIds
        case visibleMemberIds
        case note
        case attachmentUrls
        case source
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        householdId: UUID,
        creatorId: UUID,
        type: LedgerEntryType,
        amount: Double,
        currency: String,
        transactionTime: Date,
        categoryId: UUID?,
        categoryNameSnapshot: String,
        categoryIconSnapshot: String?,
        payerIds: [UUID],
        targetMemberIds: [UUID],
        visibleMemberIds: [UUID] = [],
        note: String?,
        attachmentUrls: [String],
        source: String,
        createdAt: Date,
        updatedAt: Date,
        tagSnapshots: [String] = []
    ) {
        self.id = id
        self.householdId = householdId
        self.creatorId = creatorId
        self.type = type
        self.amount = amount
        self.currency = currency
        self.transactionTime = transactionTime
        self.categoryId = categoryId
        self.categoryNameSnapshot = categoryNameSnapshot
        self.categoryIconSnapshot = categoryIconSnapshot
        self.payerIds = payerIds
        self.targetMemberIds = targetMemberIds
        self.visibleMemberIds = visibleMemberIds
        self.note = note
        self.attachmentUrls = attachmentUrls
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tagSnapshots = tagSnapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        creatorId = try container.decode(UUID.self, forKey: .creatorId)
        type = try container.decode(LedgerEntryType.self, forKey: .type)
        amount = Self.decodeAmount(from: container)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "HKD"
        transactionTime = try container.decode(Date.self, forKey: .transactionTime)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        categoryNameSnapshot = try container.decode(String.self, forKey: .categoryNameSnapshot)
        categoryIconSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryIconSnapshot)
        let decodedPayerIds = try container.decodeIfPresent([UUID].self, forKey: .payerIds) ?? []
        if decodedPayerIds.isEmpty == false {
            payerIds = decodedPayerIds
        } else if let legacyPayerId = try container.decodeIfPresent(UUID.self, forKey: .payerId) {
            payerIds = [legacyPayerId]
        } else {
            payerIds = []
        }
        targetMemberIds = try container.decodeIfPresent([UUID].self, forKey: .targetMemberIds) ?? []
        visibleMemberIds = try container.decodeIfPresent([UUID].self, forKey: .visibleMemberIds) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note)
        attachmentUrls = try container.decodeIfPresent([String].self, forKey: .attachmentUrls) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "manual"
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        tagSnapshots = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(creatorId, forKey: .creatorId)
        try container.encode(type, forKey: .type)
        try container.encode(amount, forKey: .amount)
        try container.encode(currency, forKey: .currency)
        try container.encode(transactionTime, forKey: .transactionTime)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encode(categoryNameSnapshot, forKey: .categoryNameSnapshot)
        try container.encodeIfPresent(categoryIconSnapshot, forKey: .categoryIconSnapshot)
        try container.encode(payerIds, forKey: .payerIds)
        try container.encode(targetMemberIds, forKey: .targetMemberIds)
        try container.encode(visibleMemberIds, forKey: .visibleMemberIds)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(attachmentUrls, forKey: .attachmentUrls)
        try container.encode(source, forKey: .source)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func decodeAmount(from container: KeyedDecodingContainer<CodingKeys>) -> Double {
        if let value = try? container.decode(Double.self, forKey: .amount) {
            return value
        }
        if let stringValue = try? container.decode(String.self, forKey: .amount),
           let parsed = Double(stringValue.replacingOccurrences(of: ",", with: "")) {
            return parsed
        }
        return 0
    }
}

struct TransactionTagMapping: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(transactionId.uuidString)-\(tagNameSnapshot)" }
    let transactionId: UUID
    var tagId: UUID?
    var tagNameSnapshot: String
    let createdAt: Date
}

enum LedgerReportPeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

enum LedgerCategoryMutationError: LocalizedError, Equatable {
    case hasLinkedTransactions
    case softDeleteDidNotPersist

    var errorDescription: String? {
        switch self {
        case .hasLinkedTransactions:
            AppLocalized.localizedSync(L10n.Ledger.cannotDeleteCategoryWithEntries)
        case .softDeleteDidNotPersist:
            AppLocalized.localizedSync(L10n.Ledger.deleteCategoryFailed)
        }
    }
}
