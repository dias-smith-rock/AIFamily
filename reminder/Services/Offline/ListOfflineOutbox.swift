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

/// Planner 清单离线出站队列：内存权威 + 磁盘持久化。
@MainActor
final class ListOfflineOutbox {
    static let shared = ListOfflineOutbox()

    private static let storageKey = "offline.list.outbox.v1"
    private var queue: [OfflineListMutation] = []
    private var didLoadFromDisk = false
    private var isFlushing = false

    private init() {}

    private func ensureLoaded() {
        guard didLoadFromDisk == false else { return }
        queue = LocalCacheManager.shared.load(forKey: Self.storageKey) ?? []
        didLoadFromDisk = true
    }

    func enqueue(_ mutation: OfflineListMutation) {
        ensureLoaded()
        switch mutation.kind {
        case .updateList:
            if let listId = mutation.listId {
                queue.removeAll { $0.listId == listId && $0.kind == .updateList }
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
        persist()
        #if DEBUG
        print("[ListOfflineOutbox] enqueue kind=\(mutation.kind.rawValue) pending=\(queue.count)")
        #endif
    }

    var pendingListIDs: Set<UUID> {
        ensureLoaded()
        return Set(queue.compactMap(\.listId))
    }

    var pendingItemIDs: Set<UUID> {
        ensureLoaded()
        return Set(queue.compactMap(\.itemId))
    }

    func flushIfNeeded() async {
        guard await NetworkMonitor.shared.isConnected else { return }
        ensureLoaded()
        guard isFlushing == false else { return }
        isFlushing = true
        defer { isFlushing = false }

        guard let service = AppBootstrapLocator.shared?.services.listService else {
            #if DEBUG
            print("[ListOfflineOutbox] flush aborted - listService unavailable")
            #endif
            return
        }

        var failedIDs = Set<UUID>()
        while await NetworkMonitor.shared.isConnected, queue.isEmpty == false {
            guard let index = queue.firstIndex(where: { failedIDs.contains($0.id) == false }) else {
                break
            }
            let mutation = queue[index]
            do {
                try await apply(mutation, using: service)
                queue.removeAll { $0.id == mutation.id }
                persist()
            } catch {
                #if DEBUG
                print(
                    "[ListOfflineOutbox] flush item failed kind=\(mutation.kind.rawValue) error=\(error.localizedDescription)"
                )
                #endif
                failedIDs.insert(mutation.id)
                if let currentIndex = queue.firstIndex(where: { $0.id == mutation.id }) {
                    let item = queue.remove(at: currentIndex)
                    queue.append(item)
                    persist()
                }
                if failedIDs.count >= queue.count {
                    break
                }
            }
        }
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

    private func persist() {
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
