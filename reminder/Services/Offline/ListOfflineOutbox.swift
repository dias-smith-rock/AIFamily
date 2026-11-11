import Foundation

enum OfflineListMutationKind: String, Codable, Sendable {
    case createList
    case updateList
    case deleteList
    case createItem
    case updateItem
    case deleteItem
}

struct OfflineListMutation: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: OfflineListMutationKind
    let enqueuedAt: Date
    var list: HouseholdList?
    var listId: UUID?
    var item: ListItem?
    var itemId: UUID?

    static func createList(_ list: HouseholdList) -> OfflineListMutation {
        OfflineListMutation(
            id: UUID(),
            kind: .createList,
            enqueuedAt: Date(),
            list: list,
            listId: list.id,
            item: nil,
            itemId: nil
        )
    }

    static func updateList(_ list: HouseholdList) -> OfflineListMutation {
        OfflineListMutation(
            id: UUID(),
            kind: .updateList,
            enqueuedAt: Date(),
            list: list,
            listId: list.id,
            item: nil,
            itemId: nil
        )
    }

    static func deleteList(listId: UUID) -> OfflineListMutation {
        OfflineListMutation(
            id: UUID(),
            kind: .deleteList,
            enqueuedAt: Date(),
            list: nil,
            listId: listId,
            item: nil,
            itemId: nil
        )
    }

    static func createItem(_ item: ListItem) -> OfflineListMutation {
        OfflineListMutation(
            id: UUID(),
            kind: .createItem,
            enqueuedAt: Date(),
            list: nil,
            listId: item.listId,
            item: item,
            itemId: item.id
        )
    }

    static func updateItem(_ item: ListItem) -> OfflineListMutation {
        OfflineListMutation(
            id: UUID(),
            kind: .updateItem,
            enqueuedAt: Date(),
            list: nil,
            listId: item.listId,
            item: item,
            itemId: item.id
        )
    }

    static func deleteItem(itemId: UUID, listId: UUID) -> OfflineListMutation {
        OfflineListMutation(
            id: UUID(),
            kind: .deleteItem,
            enqueuedAt: Date(),
            list: nil,
            listId: listId,
            item: nil,
            itemId: itemId
        )
    }
}

/// Planner 清单离线出站队列：本地写缓存后入队，联网 FIFO flush。
@MainActor
final class ListOfflineOutbox {
    static let shared = ListOfflineOutbox()

    private static let storageKey = "offline.list.outbox.v1"
    private var isFlushing = false

    private init() {}

    func enqueue(_ mutation: OfflineListMutation) {
        var queue = loadQueue()
        switch mutation.kind {
        case .updateList:
            if let listId = mutation.listId {
                queue.removeAll { $0.listId == listId && ($0.kind == .updateList) }
            }
        case .deleteList:
            if let listId = mutation.listId {
                queue.removeAll { $0.listId == listId }
            }
        case .updateItem:
            if let itemId = mutation.itemId {
                queue.removeAll { $0.itemId == itemId && $0.kind == .updateItem }
            }
        case .deleteItem:
            if let itemId = mutation.itemId {
                queue.removeAll { $0.itemId == itemId }
            }
        case .createList, .createItem:
            break
        }
        queue.append(mutation)
        persist(queue)
        #if DEBUG
        print("[ListOfflineOutbox] enqueue kind=\(mutation.kind.rawValue) pending=\(queue.count)")
        #endif
    }

    var pendingListIDs: Set<UUID> {
        Set(loadQueue().compactMap(\.listId))
    }

    var pendingItemIDs: Set<UUID> {
        Set(loadQueue().compactMap(\.itemId))
    }

    func flushIfNeeded() async {
        guard await NetworkMonitor.shared.isConnected else { return }
        guard isFlushing == false else { return }
        isFlushing = true
        defer { isFlushing = false }

        var queue = loadQueue()
        guard queue.isEmpty == false else { return }

        guard let service = AppBootstrapLocator.shared?.services.listService else {
            #if DEBUG
            print("[ListOfflineOutbox] flush aborted - listService unavailable")
            #endif
            return
        }

        var index = 0
        while index < queue.count {
            let mutation = queue[index]
            do {
                try await apply(mutation, using: service)
                queue.remove(at: index)
                persist(queue)
            } catch {
                #if DEBUG
                print(
                    "[ListOfflineOutbox] flush item failed kind=\(mutation.kind.rawValue) error=\(error.localizedDescription)"
                )
                #endif
                break
            }
        }
        if queue.isEmpty == false {
            persist(queue)
        }
        // 拉取通知由 `LocalFirstSyncCoordinator.syncNow` 统一发出。
    }

    private func apply(_ mutation: OfflineListMutation, using service: ListDataService) async throws {
        switch mutation.kind {
        case .createList:
            guard let list = mutation.list else { return }
            let payload = HouseholdListInsertPayload(
                id: list.id,
                householdId: list.householdId,
                creatorId: list.creatorId,
                title: list.title,
                kind: list.kind.rawValue,
                tripStartDate: list.tripStartDate,
                tripEndDate: list.tripEndDate,
                sortOrder: list.sortOrder
            )
            _ = try await service.createList(payload)
        case .updateList:
            guard let list = mutation.list else { return }
            let payload = HouseholdListUpdatePayload(
                title: list.title,
                kind: list.kind.rawValue,
                tripStartDate: list.tripStartDate,
                tripEndDate: list.tripEndDate,
                sortOrder: list.sortOrder
            )
            _ = try await service.updateList(id: list.id, payload: payload)
        case .deleteList:
            guard let listId = mutation.listId else { return }
            try await service.deleteList(id: listId)
        case .createItem:
            guard let item = mutation.item else { return }
            let payload = ListItemInsertPayload(
                id: item.id,
                listId: item.listId,
                householdId: item.householdId,
                title: item.title,
                isChecked: item.isChecked,
                note: item.note,
                sortOrder: item.sortOrder,
                creatorId: item.creatorId
            )
            _ = try await service.createItem(payload)
        case .updateItem:
            guard let item = mutation.item else { return }
            let payload = ListItemUpdatePayload(
                title: item.title,
                isChecked: item.isChecked,
                note: item.note,
                sortOrder: item.sortOrder,
                completedBy: item.completedBy,
                completedAt: item.completedAt
            )
            _ = try await service.updateItem(id: item.id, payload: payload)
        case .deleteItem:
            guard let itemId = mutation.itemId else { return }
            try await service.deleteItem(id: itemId)
        }
    }

    private func loadQueue() -> [OfflineListMutation] {
        LocalCacheManager.shared.load(forKey: Self.storageKey) ?? []
    }

    private func persist(_ queue: [OfflineListMutation]) {
        if queue.isEmpty {
            LocalCacheManager.shared.remove(forKey: Self.storageKey)
        } else {
            LocalCacheManager.shared.save(queue, forKey: Self.storageKey)
        }
    }
}

extension Notification.Name {
    static let plannerListsDidChange = Notification.Name("plannerListsDidChange")
}
