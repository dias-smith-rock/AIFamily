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

    func clearErrorMessage() {
        errorMessage = nil
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

        if let cached = await HouseholdLocalCache.loadLists(for: householdId) {
            lists = cached
        }

        guard await NetworkMonitor.shared.isConnected else { return }

        do {
            let remote = try await listService.fetchLists(in: householdId)
            lists = remote
            HouseholdLocalCache.saveLists(remote, for: householdId)
        } catch {
            if lists.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 打印用：当前打开的清单用内存数据，其余优先磁盘缓存，再向服务端补一次。
    func itemsForPrinting(listId: UUID) async -> [ListItem] {
        if activeListId == listId {
            return items
        }
        if let cached = await HouseholdLocalCache.loadListItems(for: listId) {
            return cached
        }
        return (try? await listService.fetchItems(in: listId)) ?? []
    }

    func loadItems(for listId: UUID) async {
        activeListId = listId
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if let cached = await HouseholdLocalCache.loadListItems(for: listId) {
            items = cached
        }

        guard await NetworkMonitor.shared.isConnected else { return }

        do {
            let remote = try await listService.fetchItems(in: listId)
            items = remote
            HouseholdLocalCache.saveListItems(remote, for: listId)
        } catch {
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
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

        guard await NetworkMonitor.shared.isConnected else {
            errorMessage = AppLocalized.localized(L10n.Common.networkConnectionErrorPleaseCheckYourConne)
            return nil
        }

        let now = Date()
        let draft = HouseholdList(
            id: UUID(),
            householdId: householdId,
            creatorId: membershipId,
            title: trimmed,
            kind: kind,
            tripStartDate: kind == .trip ? tripStart.map(Self.dayString(from:)) : nil,
            tripEndDate: kind == .trip ? tripEnd.map(Self.dayString(from:)) : nil,
            sortOrder: (lists.map(\.sortOrder).max() ?? -1) + 1,
            createdAt: now,
            updatedAt: now
        )
        let payload = HouseholdListInsertPayload(
            id: draft.id,
            householdId: draft.householdId,
            creatorId: draft.creatorId,
            title: draft.title,
            kind: draft.kind.rawValue,
            tripStartDate: draft.tripStartDate,
            tripEndDate: draft.tripEndDate,
            sortOrder: draft.sortOrder
        )

        do {
            let created = try await listService.createList(payload)
            lists.insert(created, at: 0)
            HouseholdLocalCache.upsertListInCache(created)
            NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func renameList(_ list: HouseholdList, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        guard await NetworkMonitor.shared.isConnected else {
            errorMessage = AppLocalized.localized(L10n.Common.networkConnectionErrorPleaseCheckYourConne)
            return
        }

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
            HouseholdLocalCache.upsertListInCache(updated)
            NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteList(_ list: HouseholdList) async {
        guard await NetworkMonitor.shared.isConnected else {
            errorMessage = AppLocalized.localized(L10n.Common.networkConnectionErrorPleaseCheckYourConne)
            return
        }

        do {
            try await listService.deleteList(id: list.id)
            lists.removeAll { $0.id == list.id }
            if activeListId == list.id {
                items = []
                activeListId = nil
            }
            HouseholdLocalCache.removeListFromCache(listId: list.id, householdId: list.householdId)
            NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
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

        guard await NetworkMonitor.shared.isConnected else {
            errorMessage = AppLocalized.localized(L10n.Common.networkConnectionErrorPleaseCheckYourConne)
            return nil
        }

        let now = Date()
        let draft = ListItem(
            id: UUID(),
            listId: list.id,
            householdId: list.householdId,
            title: trimmed,
            isChecked: false,
            note: nil,
            sortOrder: nextItemSortOrder(),
            creatorId: membershipId,
            completedBy: nil,
            completedAt: nil,
            createdAt: now,
            updatedAt: now
        )
        let payload = ListItemInsertPayload(
            id: draft.id,
            listId: draft.listId,
            householdId: draft.householdId,
            title: draft.title,
            isChecked: draft.isChecked,
            note: draft.note,
            sortOrder: draft.sortOrder,
            creatorId: draft.creatorId
        )

        do {
            let created = try await listService.createItem(payload)
            if activeListId == list.id {
                items.append(created)
            }
            HouseholdLocalCache.upsertListItemInCache(created)
            NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func toggleChecked(_ item: ListItem) async {
        guard await NetworkMonitor.shared.isConnected else {
            errorMessage = AppLocalized.localized(L10n.Common.networkConnectionErrorPleaseCheckYourConne)
            return
        }

        let nextChecked = item.isChecked == false
        let payload = ListItemUpdatePayload(
            title: item.title,
            isChecked: nextChecked,
            note: item.note,
            sortOrder: item.sortOrder,
            completedBy: nextChecked ? currentMembershipId : nil,
            completedAt: nextChecked ? Date() : nil
        )

        do {
            let updated = try await listService.updateItem(id: item.id, payload: payload)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = updated
            }
            HouseholdLocalCache.upsertListItemInCache(updated)
            NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteItem(_ item: ListItem) async {
        guard await NetworkMonitor.shared.isConnected else {
            errorMessage = AppLocalized.localized(L10n.Common.networkConnectionErrorPleaseCheckYourConne)
            return
        }

        do {
            try await listService.deleteItem(id: item.id)
            items.removeAll { $0.id == item.id }
            HouseholdLocalCache.removeListItemFromCache(itemId: item.id, listId: item.listId)
            NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
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
