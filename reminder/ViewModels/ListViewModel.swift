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

        if let cached = await HouseholdLocalCache.loadLists(for: householdId) {
            lists = mergePendingLists(cached, householdId: householdId)
        }

        guard await NetworkMonitor.shared.isConnected else { return }

        do {
            let remote = try await listService.fetchLists(in: householdId)
            let merged = mergePendingLists(remote, householdId: householdId)
            lists = merged
            HouseholdLocalCache.saveLists(merged, for: householdId)
        } catch {
            if lists.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadItems(for listId: UUID) async {
        activeListId = listId
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if let cached = await HouseholdLocalCache.loadListItems(for: listId) {
            items = mergePendingItems(cached)
        }

        guard await NetworkMonitor.shared.isConnected else { return }

        do {
            let remote = try await listService.fetchItems(in: listId)
            let merged = mergePendingItems(remote)
            items = merged
            HouseholdLocalCache.saveListItems(merged, for: listId)
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

        let now = Date()
        let created = HouseholdList(
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
        lists.insert(created, at: 0)
        HouseholdLocalCache.upsertListInCache(created)
        ListOfflineOutbox.shared.enqueue(.createList(created))
        NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        LocalFirstSyncCoordinator.requestSync(reason: "listCreate")
        return created
    }

    func renameList(_ list: HouseholdList, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        var updated = list
        updated.title = trimmed
        updated.updatedAt = Date()
        if let index = lists.firstIndex(where: { $0.id == list.id }) {
            lists[index] = updated
        }
        HouseholdLocalCache.upsertListInCache(updated)
        ListOfflineOutbox.shared.enqueue(.updateList(updated))
        NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        LocalFirstSyncCoordinator.requestSync(reason: "listUpdate")
    }

    func deleteList(_ list: HouseholdList) async {
        lists.removeAll { $0.id == list.id }
        if activeListId == list.id {
            items = []
            activeListId = nil
        }
        HouseholdLocalCache.removeListFromCache(listId: list.id, householdId: list.householdId)
        ListOfflineOutbox.shared.enqueue(.deleteList(listId: list.id))
        NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        LocalFirstSyncCoordinator.requestSync(reason: "listDelete")
    }

    @discardableResult
    func addItem(title: String, to list: HouseholdList) async -> ListItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let membershipId = currentMembershipId
        else { return nil }

        let now = Date()
        let created = ListItem(
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
        if activeListId == list.id {
            items.append(created)
        }
        HouseholdLocalCache.upsertListItemInCache(created)
        ListOfflineOutbox.shared.enqueue(.createItem(created))
        NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        LocalFirstSyncCoordinator.requestSync(reason: "listItemCreate")
        return created
    }

    func toggleChecked(_ item: ListItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let nextChecked = item.isChecked == false
        items[index].isChecked = nextChecked
        items[index].completedBy = nextChecked ? currentMembershipId : nil
        items[index].completedAt = nextChecked ? Date() : nil
        items[index].updatedAt = Date()
        let snapshot = items[index]
        HouseholdLocalCache.upsertListItemInCache(snapshot)
        ListOfflineOutbox.shared.enqueue(.updateItem(snapshot))
        NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        LocalFirstSyncCoordinator.requestSync(reason: "listItemToggle")
    }

    func deleteItem(_ item: ListItem) async {
        items.removeAll { $0.id == item.id }
        HouseholdLocalCache.removeListItemFromCache(itemId: item.id, listId: item.listId)
        ListOfflineOutbox.shared.enqueue(.deleteItem(itemId: item.id, listId: item.listId))
        NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        LocalFirstSyncCoordinator.requestSync(reason: "listItemDelete")
    }

    var openItems: [ListItem] {
        items.filter { $0.isChecked == false }
    }

    var checkedItems: [ListItem] {
        items.filter(\.isChecked)
    }

    private func mergePendingLists(_ remote: [HouseholdList], householdId: UUID) -> [HouseholdList] {
        let pendingIDs = ListOfflineOutbox.shared.pendingListIDs
        guard pendingIDs.isEmpty == false else { return remote }
        let cached = LocalCacheManager.shared.load(
            forKey: HouseholdLocalCache.listsCacheKey(for: householdId)
        ) as [HouseholdList]? ?? []
        let cachedById = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        var merged = remote.map { row in
            if pendingIDs.contains(row.id), let local = cachedById[row.id] { return local }
            return row
        }
        for id in pendingIDs {
            if merged.contains(where: { $0.id == id }) == false, let local = cachedById[id] {
                merged.insert(local, at: 0)
            }
        }
        return merged
    }

    private func mergePendingItems(_ remote: [ListItem]) -> [ListItem] {
        let pendingIDs = ListOfflineOutbox.shared.pendingItemIDs
        guard pendingIDs.isEmpty == false, let listId = activeListId else { return remote }
        let cached = LocalCacheManager.shared.load(
            forKey: HouseholdLocalCache.listItemsCacheKey(for: listId)
        ) as [ListItem]? ?? []
        let cachedById = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        var merged = remote.map { row in
            if pendingIDs.contains(row.id), let local = cachedById[row.id] { return local }
            return row
        }
        for id in pendingIDs {
            if merged.contains(where: { $0.id == id }) == false, let local = cachedById[id] {
                merged.append(local)
            }
        }
        return merged
    }

    private func nextItemSortOrder() -> Int {
        (items.map(\.sortOrder).max() ?? -1) + 1
    }

    private static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
