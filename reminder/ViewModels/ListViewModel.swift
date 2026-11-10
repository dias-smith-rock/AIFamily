import Foundation
import Combine

@MainActor
final class ListViewModel: ObservableObject {
    @Published private(set) var lists: [HouseholdList] = []
    @Published private(set) var items: [ListItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let listService: ListDataService
    private var currentHouseholdId: UUID?
    private var currentMembershipId: UUID?
    private var activeListId: UUID?

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(listService: ListDataService) {
        self.listService = listService
    }

    func setHouseholdContext(householdId: UUID?, membershipId: UUID?) {
        let householdChanged = currentHouseholdId != householdId
        currentHouseholdId = householdId
        currentMembershipId = membershipId
        if householdId == nil {
            lists = []
            items = []
            activeListId = nil
            errorMessage = nil
        } else if householdChanged {
            lists = []
            items = []
            activeListId = nil
        }
    }

    func loadLists(force: Bool = false) async {
        guard let householdId = currentHouseholdId else {
            lists = []
            return
        }
        if force == false, isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            lists = try await listService.fetchLists(in: householdId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadItems(for listId: UUID) async {
        activeListId = listId
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await listService.fetchItems(in: listId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createList(
        title: String,
        kind: ListKind,
        tripStart: Date?,
        tripEnd: Date?
    ) async -> HouseholdList? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let householdId = currentHouseholdId,
              let membershipId = currentMembershipId
        else { return nil }

        let payload = HouseholdListInsertPayload(
            id: UUID(),
            householdId: householdId,
            creatorId: membershipId,
            title: trimmed,
            kind: kind.rawValue,
            tripStartDate: kind == .trip ? tripStart.map(Self.dayString(from:)) : nil,
            tripEndDate: kind == .trip ? tripEnd.map(Self.dayString(from:)) : nil,
            sortOrder: (lists.map(\.sortOrder).max() ?? -1) + 1
        )
        do {
            let created = try await listService.createList(payload)
            lists.insert(created, at: 0)
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func renameList(_ list: HouseholdList, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let payload = HouseholdListUpdatePayload(
            title: trimmed,
            kind: list.kind.rawValue,
            tripStartDate: list.tripStartDate,
            tripEndDate: list.tripEndDate,
            sortOrder: list.sortOrder
        )
        do {
            let updated = try await listService.updateList(id: list.id, payload: payload)
            if let index = lists.firstIndex(where: { $0.id == list.id }) {
                lists[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteList(_ list: HouseholdList) async {
        do {
            try await listService.deleteList(id: list.id)
            lists.removeAll { $0.id == list.id }
            if activeListId == list.id {
                items = []
                activeListId = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func addItem(title: String, to list: HouseholdList) async -> ListItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let membershipId = currentMembershipId
        else { return nil }

        let payload = ListItemInsertPayload(
            id: UUID(),
            listId: list.id,
            householdId: list.householdId,
            title: trimmed,
            isChecked: false,
            note: nil,
            sortOrder: nextItemSortOrder(),
            creatorId: membershipId
        )
        do {
            let created = try await listService.createItem(payload)
            if activeListId == list.id {
                items.append(created)
            }
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func toggleChecked(_ item: ListItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let nextChecked = item.isChecked == false
        let previous = items[index]
        items[index].isChecked = nextChecked
        items[index].completedBy = nextChecked ? currentMembershipId : nil
        items[index].completedAt = nextChecked ? Date() : nil

        let payload = ListItemUpdatePayload(
            title: nil,
            isChecked: nextChecked,
            note: nil,
            sortOrder: nil,
            completedBy: nextChecked ? currentMembershipId : nil,
            completedAt: nextChecked ? Date() : nil
        )
        do {
            let updated = try await listService.updateItem(id: item.id, payload: payload)
            if let latest = items.firstIndex(where: { $0.id == item.id }) {
                items[latest] = updated
            }
        } catch {
            items[index] = previous
            errorMessage = error.localizedDescription
        }
    }

    func deleteItem(_ item: ListItem) async {
        do {
            try await listService.deleteItem(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var openItems: [ListItem] {
        items.filter { $0.isChecked == false }
    }

    var checkedItems: [ListItem] {
        items.filter(\.isChecked)
    }

    private func nextItemSortOrder() -> Int {
        (items.map(\.sortOrder).max() ?? -1) + 1
    }

    private static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
