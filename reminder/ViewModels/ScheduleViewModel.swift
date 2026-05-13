import Foundation
import Combine
import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var tasks: [FamilyTask] = []
    /// 当前家庭下活跃成员（`household_memberships`），用于列表「谁去办」解析。
    @Published private(set) var householdMembers: [HouseholdMembership] = []
    /// 当前家庭档案（`family_profiles`），用于列表「为了谁」头像。
    @Published private(set) var familyProfiles: [FamilyProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let taskService: TaskDataService
    private let membershipService: HouseholdMembershipDataService
    private let familyProfileService: FamilyProfileDataService
    private var currentHouseholdId: UUID?
    /// 避免在仅切换日期时重复拉取成员与档案。
    private var rosterLoadedForHouseholdId: UUID?

    #if canImport(Supabase)
    private var tasksRealtimeChannel: RealtimeChannelV2?
    private var tasksRealtimeSubscription: RealtimeSubscription?
    #endif

    /// Realtime 防抖：批量写入（如循环任务）时合并为单次拉取。
    private var realtimeRefreshTask: Task<Void, Never>?

    private var rosterChangeCancellable: AnyCancellable?

    init(
        taskService: TaskDataService,
        membershipService: HouseholdMembershipDataService,
        familyProfileService: FamilyProfileDataService
    ) {
        self.taskService = taskService
        self.membershipService = membershipService
        self.familyProfileService = familyProfileService

        rosterChangeCancellable = NotificationCenter.default
            .publisher(for: .scheduleHouseholdRosterDidChange)
            .compactMap { notification in
                notification.object as? UUID
            }
            .sink { [weak self] householdId in
                Task { @MainActor [weak self] in
                    await self?.refreshHouseholdRosterIfMatchesPostedHousehold(householdId)
                }
            }
    }

    func setHouseholdContext(_ householdId: UUID?) {
        currentHouseholdId = householdId
        if householdId == nil {
            householdMembers = []
            familyProfiles = []
            rosterLoadedForHouseholdId = nil
        } else if rosterLoadedForHouseholdId != householdId {
            rosterLoadedForHouseholdId = nil
        }
    }

    private static func tasksCacheKey(for householdId: UUID) -> String {
        "schedule.tasks.snapshot.\(householdId.uuidString.lowercased())"
    }

    func loadTasks(silent: Bool = false) async {
        guard let householdId = currentHouseholdId else {
            tasks = []
            if !silent {
                errorMessage = "当前未选择家庭。"
            }
            return
        }

        if rosterLoadedForHouseholdId != householdId {
            await loadHouseholdRoster(in: householdId)
        }

        let cacheKey = Self.tasksCacheKey(for: householdId)

        var restoredFromDisk = false
        if silent == false, let cached: [FamilyTask] = LocalCacheManager.shared.load(forKey: cacheKey) {
            tasks = cached
            errorMessage = nil
            restoredFromDisk = true
        }

        let showLoading = !silent && !restoredFromDisk
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
            let fresh = try await taskService.fetchTasks(in: householdId)
            tasks = fresh
            LocalCacheManager.shared.save(fresh, forKey: cacheKey)
            if !silent {
                errorMessage = nil
            }
        } catch {
            if !silent {
                if restoredFromDisk == false {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadHouseholdRoster(in householdId: UUID) async {
        do {
            async let memberships = membershipService.fetchMemberships(in: householdId)
            async let profiles = familyProfileService.fetchProfiles(in: householdId)
            let (rawMembers, rawProfiles) = try await (memberships, profiles)
            familyProfiles = rawProfiles
            let embedded = FamilyProfile.uniqueMembershipsFlattened(from: rawProfiles)
            let embeddedIds = Set(embedded.map(\.id))
            let orphans = rawMembers.filter { embeddedIds.contains($0.id) == false }
            let merged = embedded + orphans
            householdMembers = merged
                .filter { $0.status == .active }
                .sorted { $0.createdAt < $1.createdAt }
            rosterLoadedForHouseholdId = householdId
        } catch {
            householdMembers = []
            familyProfiles = []
            rosterLoadedForHouseholdId = nil
        }
    }

    /// 家庭页写入成员/档案后调用：`householdId` 须与当前日程上下文一致。
    func refreshHouseholdRosterIfMatchesPostedHousehold(_ householdId: UUID?) async {
        guard let householdId, householdId == currentHouseholdId else { return }
        rosterLoadedForHouseholdId = nil
        await loadHouseholdRoster(in: householdId)
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
            syncAlarms(for: createdTask)
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
            syncAlarms(for: updatedTask)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 将本地通知与任务提醒规则对齐（保存 / 导入后可调用）。
    /// 必须为**同步**方法：在首行从 `FamilyTask` 拆出 `TaskAlarmPayload`，再 `Task` 派发到通知 actor。
    /// 若把大体积 `FamilyTask` 作为 `async` 函数入参，挂起恢复后帧内副本可能损坏（更新任务时 `memcpy`/LLDB parent NULL）。
    func syncAlarms(for task: FamilyTask) {
        let payload = TaskAlarmPayload(schedulingFrom: task)
        #if DEBUG
        print(
            "[ScheduleViewModel] syncAlarms 从 FamilyTask 已抽出 DTO taskId=\(task.id) payloadTaskId=\(payload.id) isAllDay=\(payload.isAllDay)"
        )
        #endif
        Task {
            await NotificationManager.shared.syncTaskAlarms(for: payload)
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

        if status == .completed {
            await NotificationManager.shared.cancelAllPending(for: taskId)
        }

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
        await NotificationManager.shared.cancelAllPending(for: taskId)
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
