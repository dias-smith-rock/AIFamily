import Foundation

#if canImport(Supabase)
import Supabase
#endif

/// 任务离线变更类型（日程 / 待办共用 `FamilyTask`）。
enum OfflineTaskMutationKind: String, Codable, Sendable {
    case create
    case update
    case delete
    case patchStatus
}

struct OfflineTaskMutation: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: OfflineTaskMutationKind
    let enqueuedAt: Date
    /// create / update 时使用完整任务快照。
    var task: FamilyTask?
    var taskId: UUID?
    var status: TaskStatus?
    var completionLocation: TaskCompletionLocation?
    var actingMembershipId: UUID?

    static func create(_ task: FamilyTask) -> OfflineTaskMutation {
        OfflineTaskMutation(
            id: UUID(),
            kind: .create,
            enqueuedAt: Date(),
            task: task,
            taskId: task.id,
            status: nil,
            completionLocation: nil,
            actingMembershipId: nil
        )
    }

    static func update(_ task: FamilyTask) -> OfflineTaskMutation {
        OfflineTaskMutation(
            id: UUID(),
            kind: .update,
            enqueuedAt: Date(),
            task: task,
            taskId: task.id,
            status: nil,
            completionLocation: nil,
            actingMembershipId: nil
        )
    }

    static func delete(taskId: UUID) -> OfflineTaskMutation {
        OfflineTaskMutation(
            id: UUID(),
            kind: .delete,
            enqueuedAt: Date(),
            task: nil,
            taskId: taskId,
            status: nil,
            completionLocation: nil,
            actingMembershipId: nil
        )
    }

    static func patchStatus(
        taskId: UUID,
        status: TaskStatus,
        completionLocation: TaskCompletionLocation?,
        actingMembershipId: UUID?
    ) -> OfflineTaskMutation {
        OfflineTaskMutation(
            id: UUID(),
            kind: .patchStatus,
            enqueuedAt: Date(),
            task: nil,
            taskId: taskId,
            status: status,
            completionLocation: completionLocation,
            actingMembershipId: actingMembershipId
        )
    }
}

/// 任务离线出站队列：内存为权威快照，磁盘仅作持久化；flush await 期间 enqueue 不会丢项。
@MainActor
final class TaskOfflineOutbox {
    static let shared = TaskOfflineOutbox()

    private static let storageKey = "offline.task.outbox.v1"
    private var queue: [OfflineTaskMutation] = []
    private var didLoadFromDisk = false
    private var isFlushing = false

    private init() {}

    private func ensureLoaded() {
        guard didLoadFromDisk == false else { return }
        queue = LocalCacheManager.shared.load(forKey: Self.storageKey) ?? []
        didLoadFromDisk = true
    }

    func enqueue(_ mutation: OfflineTaskMutation) {
        ensureLoaded()
        if let taskId = mutation.taskId {
            switch mutation.kind {
            case .update, .patchStatus:
                queue.removeAll {
                    $0.taskId == taskId && ($0.kind == .update || $0.kind == .patchStatus)
                }
            case .delete:
                queue.removeAll { $0.taskId == taskId }
            case .create:
                break
            }
        }
        queue.append(mutation)
        persist()
        #if DEBUG
        print("[TaskOfflineOutbox] enqueue kind=\(mutation.kind.rawValue) taskId=\(mutation.taskId?.uuidString ?? "nil") pending=\(queue.count)")
        #endif
    }

    var pendingCount: Int {
        ensureLoaded()
        return queue.count
    }

    /// 尚未 flush 的 task id（pull 合并时保留本地 pending 行）。
    var pendingTaskIDs: Set<UUID> {
        ensureLoaded()
        return Set(queue.compactMap(\.taskId))
    }

    @discardableResult
    func flushIfNeeded() async -> Int {
        guard await NetworkMonitor.shared.isConnected else { return 0 }
        ensureLoaded()
        guard isFlushing == false else { return 0 }
        isFlushing = true
        defer { isFlushing = false }

        guard let service = AppBootstrapLocator.shared?.services.taskService else {
            #if DEBUG
            print("[TaskOfflineOutbox] flush aborted - taskService unavailable")
            #endif
            return 0
        }

        #if DEBUG
        print("[TaskOfflineOutbox] flush begin count=\(queue.count)")
        #endif

        var flushed = 0
        var failedIDs = Set<UUID>()

        while await NetworkMonitor.shared.isConnected, queue.isEmpty == false {
            // 跳过本轮已失败的项，避免一条坏数据堵死整队。
            guard let index = queue.firstIndex(where: { failedIDs.contains($0.id) == false }) else {
                break
            }
            let mutation = queue[index]
            do {
                let remapped = try await apply(mutation, using: service)
                queue.removeAll { $0.id == mutation.id }
                if let remapped {
                    Self.remapTaskIdentity(from: remapped.fromId, to: remapped.toId, in: &queue)
                }
                persist()
                flushed += 1
            } catch {
                #if DEBUG
                print(
                    "[TaskOfflineOutbox] flush item failed kind=\(mutation.kind.rawValue) taskId=\(mutation.taskId?.uuidString ?? "nil") error=\(error.localizedDescription)"
                )
                #endif
                failedIDs.insert(mutation.id)
                // 旋转到队尾，继续尝试后续独立变更。
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

        #if DEBUG
        print("[TaskOfflineOutbox] flush end flushed=\(flushed) remaining=\(queue.count)")
        #endif
        return flushed
    }

    @discardableResult
    private func apply(
        _ mutation: OfflineTaskMutation,
        using service: TaskDataService
    ) async throws -> (fromId: UUID, toId: UUID)? {
        switch mutation.kind {
        case .create:
            guard let task = mutation.task else {
                throw TaskOfflineMutationError.missingPayload
            }
            let created = try await service.createTask(task, geofence: task.geofence)
            if created.id != task.id {
                HouseholdLocalCache.replaceTask(fromId: task.id, with: created)
                return (task.id, created.id)
            }
            HouseholdLocalCache.upsertTaskInCache(created)
            return nil
        case .update:
            guard let task = mutation.task else {
                throw TaskOfflineMutationError.missingPayload
            }
            let updated = try await service.updateTask(task)
            HouseholdLocalCache.upsertTaskInCache(updated)
            return nil
        case .delete:
            guard let taskId = mutation.taskId else {
                throw TaskOfflineMutationError.missingPayload
            }
            try await service.deleteTask(taskId: taskId)
            return nil
        case .patchStatus:
            guard let taskId = mutation.taskId, let status = mutation.status else {
                throw TaskOfflineMutationError.missingPayload
            }
            let patched = try await service.patchTaskStatus(
                taskId: taskId,
                to: status,
                completionLocation: mutation.completionLocation,
                actingMembershipId: mutation.actingMembershipId
            )
            HouseholdLocalCache.upsertTaskInCache(patched)
            return nil
        }
    }

    private static func remapTaskIdentity(from oldId: UUID, to newId: UUID, in queue: inout [OfflineTaskMutation]) {
        guard oldId != newId else { return }
        for index in queue.indices {
            guard queue[index].taskId == oldId else { continue }
            queue[index].taskId = newId
            if let task = queue[index].task {
                queue[index].task = task.replacingIdentity(
                    id: newId,
                    createdAt: task.createdAt,
                    status: task.status
                )
            }
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

enum TaskOfflineMutationError: LocalizedError {
    case taskNotFoundLocally
    case missingPayload

    var errorDescription: String? {
        switch self {
        case .taskNotFoundLocally:
            return "Task not found in local cache."
        case .missingPayload:
            return "Offline task mutation payload is missing."
        }
    }
}

extension Notification.Name {
    static let networkDidBecomeConnected = Notification.Name("networkDidBecomeConnected")
}
