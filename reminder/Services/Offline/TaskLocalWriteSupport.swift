import Foundation

/// 任务本地优先写入：内存通知 + 磁盘缓存 + Outbox + 后台 flush。
@MainActor
enum TaskLocalWriteSupport {
    static func commitCreate(_ task: FamilyTask) {
        HouseholdLocalCache.upsertTaskInCache(task)
        TaskOfflineOutbox.shared.enqueue(.create(task))
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        LocalFirstSyncCoordinator.requestSync(reason: "taskCreate")
    }

    static func commitUpdate(_ task: FamilyTask) {
        HouseholdLocalCache.upsertTaskInCache(task)
        TaskOfflineOutbox.shared.enqueue(.update(task))
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        LocalFirstSyncCoordinator.requestSync(reason: "taskUpdate")
    }

    static func commitDelete(taskId: UUID, householdId: UUID) {
        HouseholdLocalCache.removeTaskFromCache(taskId: taskId, householdId: householdId)
        TaskOfflineOutbox.shared.enqueue(.delete(taskId: taskId))
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        LocalFirstSyncCoordinator.requestSync(reason: "taskDelete")
    }

    static func commitPatchStatus(
        taskId: UUID,
        status: TaskStatus,
        localTask: FamilyTask?,
        completionLocation: TaskCompletionLocation?,
        actingMembershipId: UUID?
    ) {
        if var local = localTask {
            local.status = status
            if let completionLocation {
                local.completionLocation = completionLocation
            }
            HouseholdLocalCache.upsertTaskInCache(local)
        }
        TaskOfflineOutbox.shared.enqueue(
            .patchStatus(
                taskId: taskId,
                status: status,
                completionLocation: completionLocation,
                actingMembershipId: actingMembershipId
            )
        )
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        LocalFirstSyncCoordinator.requestSync(reason: "taskPatchStatus")
    }

    /// 服务端拉取结果与 pending outbox 合并：pending id 保留本地缓存行。
    static func mergeFetchedTasks(
        _ fetched: [FamilyTask],
        householdId: UUID
    ) -> [FamilyTask] {
        let pendingIDs = TaskOfflineOutbox.shared.pendingTaskIDs
        guard pendingIDs.isEmpty == false else { return fetched }
        let cached = LocalCacheManager.shared.load(
            forKey: HouseholdLocalCache.tasksCacheKey(for: householdId)
        ) as [FamilyTask]? ?? []
        let cachedById = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        var merged = fetched.map { remote in
            if pendingIDs.contains(remote.id), let local = cachedById[remote.id] {
                return local
            }
            return remote
        }
        for id in pendingIDs {
            if merged.contains(where: { $0.id == id }) == false,
               let local = cachedById[id] {
                merged.append(local)
            }
        }
        return merged
    }
}
