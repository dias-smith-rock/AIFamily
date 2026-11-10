import Foundation

#if canImport(Supabase)
import Supabase
#endif

protocol ListDataService: Sendable {
    func fetchLists(in householdId: UUID) async throws -> [HouseholdList]
    func createList(_ payload: HouseholdListInsertPayload) async throws -> HouseholdList
    func updateList(id: UUID, payload: HouseholdListUpdatePayload) async throws -> HouseholdList
    func deleteList(id: UUID) async throws

    func fetchItems(in listId: UUID) async throws -> [ListItem]
    func createItem(_ payload: ListItemInsertPayload) async throws -> ListItem
    func updateItem(id: UUID, payload: ListItemUpdatePayload) async throws -> ListItem
    func deleteItem(id: UUID) async throws
}

#if canImport(Supabase)
private enum ListSupabaseTable {
    static let householdLists = "household_lists"
    static let listItems = "list_items"
}

final class SupabaseListDataService: ListDataService {
    private let provider: SupabaseProvider

    init(provider: SupabaseProvider) {
        self.provider = provider
    }

    func fetchLists(in householdId: UUID) async throws -> [HouseholdList] {
        try await provider.client
            .from(ListSupabaseTable.householdLists)
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .order("sort_order")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createList(_ payload: HouseholdListInsertPayload) async throws -> HouseholdList {
        try await provider.client
            .from(ListSupabaseTable.householdLists)
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateList(id: UUID, payload: HouseholdListUpdatePayload) async throws -> HouseholdList {
        try await provider.client
            .from(ListSupabaseTable.householdLists)
            .update(payload)
            .eq("id", value: id.uuidString.lowercased())
            .select()
            .single()
            .execute()
            .value
    }

    func deleteList(id: UUID) async throws {
        try await provider.client
            .from(ListSupabaseTable.householdLists)
            .delete()
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    func fetchItems(in listId: UUID) async throws -> [ListItem] {
        try await provider.client
            .from(ListSupabaseTable.listItems)
            .select()
            .eq("list_id", value: listId.uuidString.lowercased())
            .order("sort_order")
            .order("created_at")
            .execute()
            .value
    }

    func createItem(_ payload: ListItemInsertPayload) async throws -> ListItem {
        try await provider.client
            .from(ListSupabaseTable.listItems)
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateItem(id: UUID, payload: ListItemUpdatePayload) async throws -> ListItem {
        try await provider.client
            .from(ListSupabaseTable.listItems)
            .update(payload)
            .eq("id", value: id.uuidString.lowercased())
            .select()
            .single()
            .execute()
            .value
    }

    func deleteItem(id: UUID) async throws {
        try await provider.client
            .from(ListSupabaseTable.listItems)
            .delete()
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }
}
#endif

actor MockListDataService: ListDataService {
    private var lists: [HouseholdList] = []
    private var items: [ListItem] = []

    func fetchLists(in householdId: UUID) async throws -> [HouseholdList] {
        lists
            .filter { $0.householdId == householdId }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt > $1.createdAt
            }
    }

    func createList(_ payload: HouseholdListInsertPayload) async throws -> HouseholdList {
        let now = Date()
        let row = HouseholdList(
            id: payload.id,
            householdId: payload.householdId,
            creatorId: payload.creatorId,
            title: payload.title,
            kind: ListKind(rawValue: payload.kind) ?? .custom,
            tripStartDate: payload.tripStartDate,
            tripEndDate: payload.tripEndDate,
            sortOrder: payload.sortOrder,
            createdAt: now,
            updatedAt: now
        )
        lists.append(row)
        return row
    }

    func updateList(id: UUID, payload: HouseholdListUpdatePayload) async throws -> HouseholdList {
        guard let index = lists.firstIndex(where: { $0.id == id }) else {
            throw SupabaseServiceError.invalidResponse
        }
        lists[index].title = payload.title
        lists[index].kind = ListKind(rawValue: payload.kind) ?? lists[index].kind
        lists[index].tripStartDate = payload.tripStartDate
        lists[index].tripEndDate = payload.tripEndDate
        lists[index].sortOrder = payload.sortOrder
        lists[index].updatedAt = Date()
        return lists[index]
    }

    func deleteList(id: UUID) async throws {
        lists.removeAll { $0.id == id }
        items.removeAll { $0.listId == id }
    }

    func fetchItems(in listId: UUID) async throws -> [ListItem] {
        items
            .filter { $0.listId == listId }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
    }

    func createItem(_ payload: ListItemInsertPayload) async throws -> ListItem {
        let now = Date()
        let row = ListItem(
            id: payload.id,
            listId: payload.listId,
            householdId: payload.householdId,
            title: payload.title,
            isChecked: payload.isChecked,
            note: payload.note,
            sortOrder: payload.sortOrder,
            creatorId: payload.creatorId,
            completedBy: nil,
            completedAt: nil,
            createdAt: now,
            updatedAt: now
        )
        items.append(row)
        return row
    }

    func updateItem(id: UUID, payload: ListItemUpdatePayload) async throws -> ListItem {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw SupabaseServiceError.invalidResponse
        }
        if let title = payload.title { items[index].title = title }
        if let isChecked = payload.isChecked { items[index].isChecked = isChecked }
        if let note = payload.note { items[index].note = note }
        if let sortOrder = payload.sortOrder { items[index].sortOrder = sortOrder }
        items[index].completedBy = payload.completedBy
        items[index].completedAt = payload.completedAt
        items[index].updatedAt = Date()
        return items[index]
    }

    func deleteItem(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }
}
