import Foundation
import Combine
import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var tasks: [FamilyTask] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let taskService: TaskDataService
    private var currentHouseholdId: UUID?

    #if canImport(Supabase)
    private var tasksRealtimeChannel: RealtimeChannelV2?
    private var tasksRealtimeSubscription: RealtimeSubscription?
    #endif

    /// Realtime 防抖：批量写入（如循环任务）时合并为单次拉取。
    private var realtimeRefreshTask: Task<Void, Never>?

    init(taskService: TaskDataService) {
        self.taskService = taskService
    }

    func setHouseholdContext(_ householdId: UUID?) {
        currentHouseholdId = householdId
    }

    func loadTasks(silent: Bool = false) async {
        guard let householdId = currentHouseholdId else {
            tasks = []
            if !silent {
                errorMessage = "当前未选择家庭。"
            }
            return
        }

        let showLoading = !silent
        if showLoading {
            isLoading = true
            errorMessage = nil
        }
        defer {
            if showLoading {
                isLoading = false
            }
        }

        do {
            // `tasks` 已由 RLS 裁剪为当前登录用户在该家庭下可见的行；列表 UI 仅按日期再过滤，勿按 user id 比对 `involvedMemberIds`（其为 membership id）。
            tasks = try await taskService.fetchTasks(in: householdId)
            errorMessage = nil
        } catch {
            if !silent {
                errorMessage = error.localizedDescription
            }
        }
    }

    #if canImport(Supabase)
    func setupRealtimeListener() async {
        await stopRealtimeListener()
        guard let householdId = currentHouseholdId else { return }

        let client = SupabaseManager.shared.client
        let channelTopic = "public:tasks:\(householdId.uuidString.lowercased())"
        let channel = client.realtimeV2.channel(channelTopic)
        tasksRealtimeChannel = channel

        let filter = "household_id=eq.\(householdId.uuidString.lowercased())"
        tasksRealtimeSubscription = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "tasks",
            filter: filter
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleDebouncedRealtimeReload()
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            tasksRealtimeSubscription?.cancel()
            tasksRealtimeSubscription = nil
            tasksRealtimeChannel = nil
        }
    }

    func stopRealtimeListener() async {
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = nil

        tasksRealtimeSubscription?.cancel()
        tasksRealtimeSubscription = nil

        guard let channel = tasksRealtimeChannel else { return }
        tasksRealtimeChannel = nil
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }
    #else
    func setupRealtimeListener() async {}
    func stopRealtimeListener() async {}
    #endif

    private func scheduleDebouncedRealtimeReload() {
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self.loadTasks(silent: true)
        }
    }

    func createTask(_ task: FamilyTask) async {
        guard let householdId = currentHouseholdId else {
            errorMessage = "当前未选择家庭。"
            return
        }
        guard task.householdId == householdId else {
            errorMessage = "任务写入失败：家庭上下文不一致。"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let createdTask = try await taskService.createTask(task)
            tasks.append(createdTask)
            tasks.sort { lhs, rhs in
                (lhs.dueDate ?? lhs.createdAt) < (rhs.dueDate ?? rhs.createdAt)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTask(_ task: FamilyTask) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let updatedTask = try await taskService.updateTask(task)
            guard let index = tasks.firstIndex(where: { $0.id == updatedTask.id }) else {
                await loadTasks()
                return
            }
            tasks[index] = updatedTask
            tasks.sort { lhs, rhs in
                (lhs.dueDate ?? lhs.createdAt) < (rhs.dueDate ?? rhs.createdAt)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTaskStatus(taskId: UUID, to status: TaskStatus) async {
        guard let currentTask = tasks.first(where: { $0.id == taskId }) else { return }
        var updatedTask = currentTask
        updatedTask.status = status
        await updateTask(updatedTask)
    }

    /// 成员详情页状态机：仅 PATCH `status`，避免整行写入与并发覆盖。
    func patchTaskStatus(taskId: UUID, to status: TaskStatus) async throws -> FamilyTask {
        errorMessage = nil

        let updated = try await taskService.patchTaskStatus(taskId: taskId, to: status)
        if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
            tasks[index] = updated
        } else {
            tasks.append(updated)
        }
        tasks.sort { lhs, rhs in
            (lhs.dueDate ?? lhs.createdAt) < (rhs.dueDate ?? rhs.createdAt)
        }
        return updated
    }

    func deleteTask(taskId: UUID) async {
        errorMessage = nil
        do {
            try await taskService.deleteTask(taskId: taskId)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                tasks.removeAll { $0.id == taskId }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
