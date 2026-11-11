import Foundation

/// 任务写入：必须联网，服务端成功后再写本地缓存；失败不落盘。
@MainActor
enum TaskLocalWriteSupport {
    enum WriteError: LocalizedError {
        case offline
        case serviceUnavailable

        var errorDescription: String? {
            switch self {
            case .offline:
                return AppLocalized.localizedSync(L10n.Common.networkConnectionErrorPleaseCheckYourConne)
            case .serviceUnavailable:
                return AppLocalized.localizedSync(L10n.Common.supabaseSdkIsNotAvailableInThisBuild)
            }
        }
    }

    static func commitCreate(_ task: FamilyTask) async throws -> FamilyTask {
        try await ensureOnline()
        let service = try taskService()
        let created = try await service.createTask(task, geofence: task.geofence)
        HouseholdLocalCache.upsertTaskInCache(created)
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        return created
    }

    static func commitUpdate(_ task: FamilyTask) async throws -> FamilyTask {
        try await ensureOnline()
        let service = try taskService()
        let updated = try await service.updateTask(task)
        HouseholdLocalCache.upsertTaskInCache(updated)
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        return updated
    }

    static func commitDelete(taskId: UUID, householdId: UUID) async throws {
        try await ensureOnline()
        let service = try taskService()
        try await service.deleteTask(taskId: taskId)
        HouseholdLocalCache.removeTaskFromCache(taskId: taskId, householdId: householdId)
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
    }

    static func commitPatchStatus(
        taskId: UUID,
        status: TaskStatus,
        localTask: FamilyTask?,
        completionLocation: TaskCompletionLocation?,
        actingMembershipId: UUID?
    ) async throws -> FamilyTask {
        try await ensureOnline()
        let service = try taskService()
        let patched = try await service.patchTaskStatus(
            taskId: taskId,
            to: status,
            completionLocation: completionLocation,
            actingMembershipId: actingMembershipId
        )
        HouseholdLocalCache.upsertTaskInCache(patched)
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        _ = localTask
        return patched
    }

    /// 拉取结果直接采用服务端快照（任务写路径已改为线上确认后落本地）。
    static func mergeFetchedTasks(
        _ fetched: [FamilyTask],
        householdId: UUID
    ) -> [FamilyTask] {
        _ = householdId
        return fetched
    }

    private static func ensureOnline() async throws {
        guard await NetworkMonitor.shared.isConnected else {
            throw WriteError.offline
        }
    }

    private static func taskService() throws -> TaskDataService {
        guard let service = AppBootstrapLocator.shared?.services.taskService else {
            throw WriteError.serviceUnavailable
        }
        return service
    }
}
