import Foundation

/// `household_lists.kind`
enum ListKind: String, Codable, Equatable, CaseIterable, Identifiable, Sendable {
    case shopping
    case trip
    case custom

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .shopping: "cart"
        case .trip: "suitcase"
        case .custom: "list.bullet"
        }
    }
}

/// `household_lists` 行。
struct HouseholdList: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var householdId: UUID
    /// `household_memberships.id`
    var creatorId: UUID
    var title: String
    var kind: ListKind
    /// Postgres `date` → `yyyy-MM-dd` 字符串（与 `birth_date` 同策略）。
    var tripStartDate: String?
    var tripEndDate: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case householdId
        case creatorId
        case title
        case kind
        case tripStartDate
        case tripEndDate
        case sortOrder
        case createdAt
        case updatedAt
    }
}

/// `list_items` 行。
struct ListItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var listId: UUID
    var householdId: UUID
    var title: String
    var isChecked: Bool
    var note: String?
    var sortOrder: Int
    /// `household_memberships.id`
    var creatorId: UUID
    /// `household_memberships.id`
    var completedBy: UUID?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case listId
        case householdId
        case title
        case isChecked
        case note
        case sortOrder
        case creatorId
        case completedBy
        case completedAt
        case createdAt
        case updatedAt
    }
}

struct HouseholdListInsertPayload: Encodable, Sendable {
    let id: UUID
    let householdId: UUID
    let creatorId: UUID
    let title: String
    let kind: String
    let tripStartDate: String?
    let tripEndDate: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case creatorId = "creator_id"
        case title
        case kind
        case tripStartDate = "trip_start_date"
        case tripEndDate = "trip_end_date"
        case sortOrder = "sort_order"
    }
}

struct HouseholdListUpdatePayload: Encodable, Sendable {
    let title: String
    let kind: String
    let tripStartDate: String?
    let tripEndDate: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case title
        case kind
        case tripStartDate = "trip_start_date"
        case tripEndDate = "trip_end_date"
        case sortOrder = "sort_order"
    }
}

struct ListItemInsertPayload: Encodable, Sendable {
    let id: UUID
    let listId: UUID
    let householdId: UUID
    let title: String
    let isChecked: Bool
    let note: String?
    let sortOrder: Int
    let creatorId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case listId = "list_id"
        case householdId = "household_id"
        case title
        case isChecked = "is_checked"
        case note
        case sortOrder = "sort_order"
        case creatorId = "creator_id"
    }
}

struct ListItemUpdatePayload: Encodable, Sendable {
    let title: String?
    let isChecked: Bool?
    let note: String?
    let sortOrder: Int?
    let completedBy: UUID?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case title
        case isChecked = "is_checked"
        case note
        case sortOrder = "sort_order"
        case completedBy = "completed_by"
        case completedAt = "completed_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        if let isChecked {
            try container.encode(isChecked, forKey: .isChecked)
            if isChecked {
                try container.encodeIfPresent(completedBy, forKey: .completedBy)
                try container.encodeIfPresent(completedAt, forKey: .completedAt)
            } else {
                // 取消勾选须显式写 null，否则 encodeIfPresent 会跳过字段。
                try container.encodeNil(forKey: .completedBy)
                try container.encodeNil(forKey: .completedAt)
            }
        } else {
            try container.encodeIfPresent(completedBy, forKey: .completedBy)
            try container.encodeIfPresent(completedAt, forKey: .completedAt)
        }
    }
}
