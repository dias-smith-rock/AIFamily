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

/// 任务离线出站队列：乐观写本地缓存后入队，恢复网络再 FIFO flush。
@MainActor
final class TaskOfflineOutbox {
    static let shared = TaskOfflineOutbox()

    private static let storageKey = "offline.task.outbox.v1"
    private var isFlushing = false

    private init() {}

    func enqueue(_ mutation: OfflineTaskMutation) {
        var queue = loadQueue()
        // 同 task 的后续 update/patch/delete 覆盖更早的同类写，减少冗余。
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
        persist(queue)
        #if DEBUG
        print("[TaskOfflineOutbox] enqueue kind=\(mutation.kind.rawValue) taskId=\(mutation.taskId?.uuidString ?? "nil") pending=\(queue.count)")
        #endif
    }

    var pendingCount: Int { loadQueue().count }

    func flushIfNeeded() async {
        guard await NetworkMonitor.shared.isConnected else { return }
        guard isFlushing == false else { return }
        isFlushing = true
        defer { isFlushing = false }

        var queue = loadQueue()
        guard queue.isEmpty == false else { return }

        #if DEBUG
        print("[TaskOfflineOutbox] flush begin count=\(queue.count)")
        #endif

        guard let service = AppBootstrapLocator.shared?.services.taskService else {
            #if DEBUG
            print("[TaskOfflineOutbox] flush aborted - taskService unavailable")
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
                    "[TaskOfflineOutbox] flush item failed kind=\(mutation.kind.rawValue) taskId=\(mutation.taskId?.uuidString ?? "nil") error=\(error.localizedDescription)"
                )
                #endif
                // 保留失败项及后续项，下次联网再试。
                break
            }
        }

        if queue.isEmpty == false {
            persist(queue)
        }
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        #if DEBUG
        print("[TaskOfflineOutbox] flush end remaining=\(queue.count)")
        #endif
    }

    private func apply(_ mutation: OfflineTaskMutation, using service: TaskDataService) async throws {
        switch mutation.kind {
        case .create:
            guard let task = mutation.task else { return }
            _ = try await service.createTask(task)
        case .update:
            guard let task = mutation.task else { return }
            _ = try await service.updateTask(task)
        case .delete:
            guard let taskId = mutation.taskId else { return }
            try await service.deleteTask(taskId: taskId)
        case .patchStatus:
            guard let taskId = mutation.taskId, let status = mutation.status else { return }
            _ = try await service.patchTaskStatus(
                taskId: taskId,
                to: status,
                completionLocation: mutation.completionLocation,
                actingMembershipId: mutation.actingMembershipId
            )
        }
    }

    private func loadQueue() -> [OfflineTaskMutation] {
        LocalCacheManager.shared.load(forKey: Self.storageKey) ?? []
    }

    private func persist(_ queue: [OfflineTaskMutation]) {
        if queue.isEmpty {
            LocalCacheManager.shared.remove(forKey: Self.storageKey)
        } else {
            LocalCacheManager.shared.save(queue, forKey: Self.storageKey)
        }
    }
}

enum TaskOfflineMutationError: LocalizedError {
    case taskNotFoundLocally

    var errorDescription: String? {
        switch self {
        case .taskNotFoundLocally:
            return "Task not found in local cache."
        }
    }
}

extension Notification.Name {
    static let networkDidBecomeConnected = Notification.Name("networkDidBecomeConnected")
}
