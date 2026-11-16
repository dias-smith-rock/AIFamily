import Foundation
import Combine

@MainActor
final class ListViewModel: ObservableObject {
    @Published private(set) var lists: [HouseholdList] = []
    @Published private(set) var items: [ListItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// 当前 space 的清单是否已经用缓存或服务端结果画过一次。没有快照时保持 false，避免空态闪一下。
    @Published private(set) var didFinishListsLoad = false
    /// 当前打开的清单条目是否已经用缓存或服务端结果画过一次。
    @Published private(set) var didFinishItemsLoad = false
    @Published private(set) var activeListId: UUID?

    private let listService: ListDataService
    private var currentHouseholdId: UUID?
    private var currentMembershipId: UUID?
    private var viewerProfileId: UUID?
    /// 当前要一起查看的 space。默认 space 由界面排到第一组。
    private var viewHouseholdIds: [UUID] = []
    /// 切换 space 或新建清单后作废进行中的列表刷新，避免旧请求盖掉刚保存的清单。
    private var listsLoadGeneration = 0
    private var itemsLoadGeneration = 0

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

    func setHouseholdContext(householdId: UUID?, membershipId: UUID?, profileId: UUID? = nil) {
        let householdChanged = currentHouseholdId != householdId
        currentHouseholdId = householdId
        currentMembershipId = membershipId
        if let profileId {
            viewerProfileId = profileId
        }
        if householdId == nil, viewHouseholdIds.isEmpty {
            lists = []
            items = []
            activeListId = nil
            didFinishListsLoad = true
            didFinishItemsLoad = false
            errorMessage = nil
        } else if householdChanged {
            items = []
            activeListId = nil
            didFinishItemsLoad = false
        }
    }

    func setViewHouseholdIds(_ ids: [UUID]) {
        guard viewHouseholdIds != ids else { return }
        viewHouseholdIds = ids
        applyCachedLists(for: effectiveViewHouseholdIds)
    }

    /// 按默认 space 在前、其余选中 space 保持原顺序，分组返回清单。
    func groupedLists(primaryHouseholdId: UUID?) -> [(id: UUID, lists: [HouseholdList])] {
        var order = effectiveViewHouseholdIds
        if let primaryHouseholdId, order.contains(primaryHouseholdId) {
            order = [primaryHouseholdId] + order.filter { $0 != primaryHouseholdId }
        }
        var seen = Set<UUID>()
        return order.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return (id, lists.filter { $0.householdId == id })
        }
    }

    private var effectiveViewHouseholdIds: [UUID] {
        if viewHouseholdIds.isEmpty == false { return viewHouseholdIds }
        if let currentHouseholdId { return [currentHouseholdId] }
        return []
    }

    private func applyCachedLists(for householdIds: [UUID]) {
        let allowed = Set(householdIds)
        lists.removeAll { allowed.contains($0.householdId) == false }
        for id in householdIds where lists.contains(where: { $0.householdId == id }) == false {
            if let cached = HouseholdLocalCache.loadListsNow(for: id) {
                lists.append(contentsOf: cached)
            }
        }
        if lists.isEmpty == false {
            didFinishListsLoad = true
        }
    }

    private func replaceLists(_ remote: [HouseholdList], for householdId: UUID) {
        let merged = Self.mergePendingLists(remote, householdId: householdId)
        lists.removeAll { $0.householdId == householdId }
        lists.append(contentsOf: merged)
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    func loadLists(force: Bool = false) async {
        let householdIds = effectiveViewHouseholdIds
        guard householdIds.isEmpty == false else {
            lists = []
            didFinishListsLoad = true
            return
        }
        if force == false, isLoading { return }
        applyCachedLists(for: householdIds)
        listsLoadGeneration += 1
        let generation = listsLoadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if generation == listsLoadGeneration {
                isLoading = false
                didFinishListsLoad = true
                publishWidgetSnapshot()
            }
        }

        guard await NetworkMonitor.shared.isConnected else { return }

        for householdId in householdIds {
            guard generation == listsLoadGeneration else { return }
            do {
                let remote = try await listService.fetchLists(in: householdId)
                guard generation == listsLoadGeneration, effectiveViewHouseholdIds.contains(householdId) else { return }
                let merged = Self.mergePendingLists(remote, householdId: householdId)
                replaceLists(merged, for: householdId)
                HouseholdLocalCache.saveLists(merged, for: householdId)
            } catch {
                guard generation == listsLoadGeneration else { return }
            if lists.isEmpty {
                errorMessage = error.localizedDescription
            }
            }
        }
    }

    /// 打开清单详情前同步铺上该清单的缓存条目，避免先看到空白再等网络。
    func presentCachedItems(for listId: UUID) {
        if activeListId == listId, didFinishItemsLoad || items.isEmpty == false {
            return
        }
        activeListId = listId
        if let cached = HouseholdLocalCache.loadListItemsNow(for: listId) {
            items = cached
            didFinishItemsLoad = true
        } else {
            items = []
            didFinishItemsLoad = false
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
        itemsLoadGeneration += 1
        let generation = itemsLoadGeneration
        presentCachedItems(for: listId)
        isLoading = true
        errorMessage = nil
        defer {
            if generation == itemsLoadGeneration {
                isLoading = false
                didFinishItemsLoad = true
                publishWidgetSnapshot()
            }
        }

        guard await NetworkMonitor.shared.isConnected else { return }

        do {
            let remote = try await listService.fetchItems(in: listId)
            guard generation == itemsLoadGeneration, activeListId == listId else { return }
            let merged = Self.mergePendingItems(remote, listId: listId)
            if items != merged {
                items = merged
            }
            HouseholdLocalCache.saveListItems(merged, for: listId)
        } catch {
            guard generation == itemsLoadGeneration else { return }
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
        upsertLocalList(draft)
        enqueuePlannerChange(.createList(draft))
        return draft
    }

    func renameList(_ list: HouseholdList, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        var updated = list
        updated.title = trimmed
        updated.updatedAt = Date()
        upsertLocalList(updated)
        enqueuePlannerChange(.updateList(updated))
    }

    func deleteList(_ list: HouseholdList) async {
        lists.removeAll { $0.id == list.id }
        if activeListId == list.id {
            items = []
            activeListId = nil
        }
        HouseholdLocalCache.removeListFromCache(listId: list.id, householdId: list.householdId)
        enqueuePlannerChange(.deleteList(listId: list.id))
    }

    @discardableResult
    func addItem(title: String, to list: HouseholdList) async -> ListItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let membershipId = currentMembershipId
        else { return nil }

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
        if activeListId == list.id {
            items.append(draft)
        }
        HouseholdLocalCache.upsertListItemInCache(draft)
        enqueuePlannerChange(.createItem(draft))
        return draft
    }

    func toggleChecked(_ item: ListItem) async {
        let nextChecked = item.isChecked == false
        var updated = item
        updated.isChecked = nextChecked
        updated.completedBy = nextChecked ? currentMembershipId : nil
        updated.completedAt = nextChecked ? Date() : nil
        updated.updatedAt = Date()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updated
        }
        HouseholdLocalCache.upsertListItemInCache(updated)
        enqueuePlannerChange(.updateItem(updated))
    }

    func deleteItem(_ item: ListItem) async {
        items.removeAll { $0.id == item.id }
        HouseholdLocalCache.removeListItemFromCache(itemId: item.id, listId: item.listId)
        enqueuePlannerChange(.deleteItem(itemId: item.id, listId: item.listId))
    }

    var openItems: [ListItem] {
        items.filter { $0.isChecked == false }
    }

    var checkedItems: [ListItem] {
        items.filter(\.isChecked)
    }

    private func upsertLocalList(_ list: HouseholdList) {
        if let index = lists.firstIndex(where: { $0.id == list.id }) {
            lists[index] = list
        } else if effectiveViewHouseholdIds.contains(list.householdId) {
            lists.insert(list, at: 0)
        }
        HouseholdLocalCache.upsertListInCache(list)
        didFinishListsLoad = true
    }

    private func enqueuePlannerChange(_ mutation: OfflineListMutation) {
        errorMessage = nil
        ListOfflineOutbox.shared.enqueue(mutation)
        LocalFirstSyncCoordinator.requestSync(reason: "plannerLocalWrite")
        NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() {
        let householdId = currentHouseholdId
        ScheduleWidgetPublisher.refreshFromCache(householdId: householdId, profileId: viewerProfileId)
    }

    private static func mergePendingLists(_ remote: [HouseholdList], householdId: UUID) -> [HouseholdList] {
        var merged = remote
        for mutation in ListOfflineOutbox.shared.pendingMutations() {
            switch mutation.kind {
            case .createList, .updateList:
                guard let list = mutation.list, list.householdId == householdId else { continue }
                if let index = merged.firstIndex(where: { $0.id == list.id }) {
                    merged[index] = list
                } else {
                    merged.insert(list, at: 0)
                }
            case .deleteList:
                if let listId = mutation.listId {
                    merged.removeAll { $0.id == listId }
                }
            case .createItem, .updateItem, .deleteItem:
                break
            }
        }
        return merged
    }

    private static func mergePendingItems(_ remote: [ListItem], listId: UUID) -> [ListItem] {
        var merged = remote
        for mutation in ListOfflineOutbox.shared.pendingMutations() where mutation.listId == listId {
            switch mutation.kind {
            case .createItem, .updateItem:
                guard let item = mutation.item else { continue }
                if let index = merged.firstIndex(where: { $0.id == item.id }) {
                    merged[index] = item
                } else {
                    merged.append(item)
                }
            case .deleteItem:
                if let itemId = mutation.itemId {
                    merged.removeAll { $0.id == itemId }
                }
            case .createList, .updateList, .deleteList:
                break
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
