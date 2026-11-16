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

    func setHouseholdContext(householdId: UUID?, membershipId: UUID?) {
        let householdChanged = currentHouseholdId != householdId
        currentHouseholdId = householdId
        currentMembershipId = membershipId
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
        lists.removeAll { $0.householdId == householdId }
        lists.append(contentsOf: remote)
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
            }
        }

        guard await NetworkMonitor.shared.isConnected else { return }

        for householdId in householdIds {
            guard generation == listsLoadGeneration else { return }
            do {
                let remote = try await listService.fetchLists(in: householdId)
                guard generation == listsLoadGeneration, effectiveViewHouseholdIds.contains(householdId) else { return }
                replaceLists(remote, for: householdId)
                HouseholdLocalCache.saveLists(remote, for: householdId)
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
            }
        }

        guard await NetworkMonitor.shared.isConnected else { return }

        do {
            let remote = try await listService.fetchItems(in: listId)
            guard generation == itemsLoadGeneration, activeListId == listId else { return }
            if items != remote {
                items = remote
            }
            HouseholdLocalCache.saveListItems(remote, for: listId)
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
            listsLoadGeneration += 1
            guard effectiveViewHouseholdIds.contains(created.householdId) else { return created }
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
