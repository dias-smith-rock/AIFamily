import Foundation
import Combine
import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var tasks: [FamilyTask] = []

    /// 日程 Tab：仅 `task_type == scheduled`（历史 `nil` 视为 scheduled），排除生日等系统任务。
    var scheduledTasks: [FamilyTask] {
        tasks.filter(\.isScheduledCalendarTask)
    }

    /// 待办 Tab：`task_type == flexible`。
    var flexibleTasks: [FamilyTask] {
        tasks.filter(\.isFlexibleTodo)
    }
    /// 当前家庭下活跃成员（`household_memberships`），用于列表「谁去办」解析。
    @Published private(set) var householdMembers: [HouseholdMembership] = []
    /// 当前家庭档案（`family_profiles`），用于列表「为了谁」头像。
    @Published private(set) var familyProfiles: [FamilyProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// 列表滚动时当前视野内的月份（用于顶栏动态标题）。
    @Published var currentVisibleDate: Date = Calendar.current.startOfDay(for: Date())

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
    private var disbandCancellable: AnyCancellable?

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

        disbandCancellable = NotificationCenter.default
            .publisher(for: .householdDidDisband)
            .compactMap { $0.object as? UUID }
            .sink { [weak self] householdId in
                Task { @MainActor [weak self] in
                    self?.purgeLocalDataForDisbandedHousehold(householdId)
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
                errorMessage = AppLocalized.localized("当前未选择群组。")
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
            let roster = try await membershipService.fetchMemberRoster(in: householdId, activeOnly: true)
                .filteredToActiveMembers(in: householdId)
            familyProfiles = roster.profiles
            let embedded = FamilyProfile.uniqueMembershipsFlattened(from: roster.profiles)
            let embeddedIds = Set(embedded.map(\.id))
            let orphans = roster.memberships.filter { embeddedIds.contains($0.id) == false }
            let merged = embedded + orphans
            householdMembers = merged
                .filter { $0.isActiveMembership() }
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

    func purgeLocalDataForDisbandedHousehold(_ householdId: UUID) {
        tasks = []
        householdMembers = []
        familyProfiles = []
        rosterLoadedForHouseholdId = nil
        if currentHouseholdId == householdId {
            currentHouseholdId = nil
        }
        LocalCacheManager.shared.remove(forKey: Self.tasksCacheKey(for: householdId))
        #if canImport(Supabase)
        Task {
            await stopRealtimeListener()
        }
        #endif
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
            errorMessage = AppLocalized.localized("当前未选择群组。")
            return
        }
        guard task.householdId == householdId else {
            errorMessage = AppLocalized.localized("任务写入失败：群组上下文不一致。")
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

    func displayTitle(for task: FamilyTask) -> String {
        TaskDisplayResolver.resolvedTitle(
            for: task,
            profiles: familyProfiles,
            locale: AppSettingsManager.shared.appLocale
        )
    }

    /// 将本地通知与任务提醒规则对齐（保存 / 导入后可调用）。
    /// 必须为**同步**方法：在首行从 `FamilyTask` 拆出 `TaskAlarmPayload`，再 `Task` 派发到通知 actor。
    /// 若把大体积 `FamilyTask` 作为 `async` 函数入参，挂起恢复后帧内副本可能损坏（更新任务时 `memcpy`/LLDB parent NULL）。
    func syncAlarms(for task: FamilyTask) {
        let payload = TaskAlarmPayload(
            schedulingFrom: task,
            profiles: familyProfiles,
            locale: AppSettingsManager.shared.appLocale
        )
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
    func patchTaskStatus(
        taskId: UUID,
        to status: TaskStatus,
        completionLocation: TaskCompletionLocation? = nil,
        actingMembershipId: UUID? = nil
    ) async throws -> FamilyTask {
        errorMessage = nil

        let updated = try await taskService.patchTaskStatus(
            taskId: taskId,
            to: status,
            completionLocation: completionLocation,
            actingMembershipId: actingMembershipId
        )
        if status == .completed {
            await NotificationManager.shared.cancelAllPending(for: taskId)
        } else {
            syncAlarms(for: updated)
        }
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

    func noteVisibleMonth(containing day: Date) {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) else {
            return
        }
        if calendar.isDate(monthStart, equalTo: currentVisibleDate, toGranularity: .month) == false {
            currentVisibleDate = monthStart
        }
    }

    /// 列表模式智能滚动：今天首个定时日程；若无则今天之后最近一条（不含灵活待办）。
    func getTargetTaskId() -> UUID? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sorted = scheduledTasks.sorted { listAnchorDate(for: $0) < listAnchorDate(for: $1) }

        if let todayTask = sorted.first(where: { calendar.isDate(listAnchorDate(for: $0), inSameDayAs: today) }) {
            return todayTask.id
        }

        if let futureTask = sorted.first(where: { calendar.startOfDay(for: listAnchorDate(for: $0)) > today }) {
            return futureTask.id
        }

        return nil
    }

    private func listAnchorDate(for task: FamilyTask) -> Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    func assigneeLabel(for task: FamilyTask, locale: Locale) -> String {
        if task.involvesWholeHousehold {
            return AppLocalized.string("所有人", locale: locale)
        }
        guard let ids = task.involvedMemberIds, ids.isEmpty == false else {
            return AppLocalized.string("所有人", locale: locale)
        }
        let names = ids.compactMap { id in
            MemberDisplayName.displayName(
                forMembershipId: id,
                members: householdMembers,
                profiles: familyProfiles
            )
        }
        if names.isEmpty {
            if ids.count == 1 {
                return AppLocalized.string("成员", locale: locale)
            }
            return String(
                format: AppLocalized.string("%lld 人", locale: locale),
                ids.count
            )
        }
        return names.joined(separator: AppLocalized.string(", ", locale: locale))
    }

    func forWhomAvatarSources(for task: FamilyTask) -> [TaskCardAvatarSource] {
        let ids = orderedTargetProfileIDs(for: task)
        guard ids.isEmpty == false else { return [] }
        let profileById = Dictionary(uniqueKeysWithValues: familyProfiles.map { ($0.id, $0) })
        return ids.compactMap { id in
            guard let profile = profileById[id] else { return nil }
            return TaskCardAvatarSource(
                id: profile.id,
                displayName: profile.displayName,
                imageURL: profile.avatarUrl.flatMap { URL(string: $0) }
            )
        }
    }

    private func orderedTargetProfileIDs(for task: FamilyTask) -> [UUID] {
        var ordered: [UUID] = []
        var seen = Set<UUID>()
        if let multi = task.targetProfileIds {
            for id in multi where seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        if let single = task.targetProfileId, seen.insert(single).inserted {
            ordered.append(single)
        }
        return ordered
    }

    func deleteTask(taskId: UUID) async {
        errorMessage = nil
        await NotificationManager.shared.cancelAllPending(for: taskId)
        do {
            try await taskService.deleteTask(taskId: taskId)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                tasks.removeAll { $0.id == taskId }
            }
            syncUpcomingLocalNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 预调度本地通知：取未来未完成任务，按时间升序后交给通知管理器（内部会截前 10 条）。
    private func syncUpcomingLocalNotifications() {
        let now = Date()
        var upcoming: [TaskAlarmPayload] = []
        var staleTaskIds: [UUID] = []

        for task in tasks {
            let payload = TaskAlarmPayload(
                schedulingFrom: task,
                profiles: familyProfiles,
                locale: AppSettingsManager.shared.appLocale
            )
            let isUpcoming: Bool = {
                guard let due = task.alarmAnchorDate else { return false }
                guard due > now else { return false }
                switch task.status {
                case .completed, .cancelled, .failed, .expired:
                    return false
                default:
                    return true
                }
            }()

            if isUpcoming {
                upcoming.append(payload)
            } else {
                staleTaskIds.append(task.id)
            }
        }

        upcoming.sort { lhs, rhs in
            (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }

        for payload in upcoming.dropFirst(10) {
            staleTaskIds.append(payload.id)
        }

        Task {
            await NotificationManager.shared.syncLocalNotifications(
                upcomingTasks: upcoming,
                cancelForTaskIds: staleTaskIds
            )
        }
    }
}
