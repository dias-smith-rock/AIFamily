import Foundation
import Combine
import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class TodoListViewModel: ObservableObject {
    @Published private(set) var flexibleTasks: [FamilyTask] = []
    @Published private(set) var completedTasks: [FamilyTask] = []
    /// 白板垃圾桶：软删除（`cancelled`）的灵活待办。
    @Published private(set) var deletedTasks: [FamilyTask] = []
    @Published private(set) var householdMembers: [HouseholdMembership] = []
    @Published private(set) var familyProfiles: [FamilyProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// 在 `task_attachments` 中有附件的任务 id（用于待办卡片角标）。
    @Published private(set) var taskIDsWithAttachments: Set<UUID> = []

    private let taskService: TaskDataService
    private let membershipService: HouseholdMembershipDataService
    private let familyProfileService: FamilyProfileDataService
    private var currentHouseholdId: UUID?
    private var viewHouseholdIds: [UUID] = []
    private var rosterLoadedForHouseholdId: UUID?
    /// 当前查看集合是否已有内存数据；切 Tab 回来时不重复拉网。
    private var loadedViewToken: String?
    private var reloadCancellable: AnyCancellable?
    /// 已发起硬删、短暂屏蔽回写的任务（避免清空后即时 fetch / 缓存覆盖把条目弹回）。
    private var pendingHardDeletedTaskIDs: Set<UUID> = []

    init(
        taskService: TaskDataService,
        membershipService: HouseholdMembershipDataService,
        familyProfileService: FamilyProfileDataService
    ) {
        self.taskService = taskService
        self.membershipService = membershipService
        self.familyProfileService = familyProfileService

        reloadCancellable = NotificationCenter.default
            .publisher(for: .scheduleTasksDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadTasks(silent: true, force: true)
                }
            }
    }

    func setHouseholdContext(_ householdId: UUID?) {
        let householdChanged = currentHouseholdId != householdId
        currentHouseholdId = householdId
        if householdId == nil {
            flexibleTasks = []
            completedTasks = []
            deletedTasks = []
            taskIDsWithAttachments = []
            householdMembers = []
            familyProfiles = []
            rosterLoadedForHouseholdId = nil
            loadedViewToken = nil
        } else if householdChanged {
            loadedViewToken = nil
            if rosterLoadedForHouseholdId != householdId {
                rosterLoadedForHouseholdId = nil
            }
        }
    }

    func setViewHouseholdIds(_ ids: [UUID]) {
        if viewHouseholdIds != ids {
            loadedViewToken = nil
        }
        viewHouseholdIds = ids
    }

    private var effectiveViewHouseholdIds: [UUID] {
        if viewHouseholdIds.isEmpty == false { return viewHouseholdIds }
        if let currentHouseholdId { return [currentHouseholdId] }
        return []
    }

    private var viewToken: String {
        effectiveViewHouseholdIds.map(\.uuidString).sorted().joined(separator: ",")
    }

    private static func tasksCacheKey(for householdId: UUID) -> String {
        HouseholdLocalCache.tasksCacheKey(for: householdId)
    }

    /// 首次进入或切换群组时加载；已有内存缓存则跳过网络请求。
    func loadTasksIfNeeded() async {
        let householdIds = effectiveViewHouseholdIds
        guard householdIds.isEmpty == false else {
            flexibleTasks = []
            completedTasks = []
            deletedTasks = []
            taskIDsWithAttachments = []
            errorMessage = AppLocalized.localized(L10n.Family.noGroupIsCurrentlySelected)
            return
        }

        let hasLocalTodos =
            flexibleTasks.isEmpty == false
            || completedTasks.isEmpty == false
            || deletedTasks.isEmpty == false

        if loadedViewToken == viewToken, hasLocalTodos {
            // 已有展示数据：静默拉网；有差距再刷新（附件角标一并更新）。
            await loadTasks(silent: true, force: true)
            return
        }

        await loadTasks(silent: false)
    }

    func loadTasks(silent: Bool = false, force: Bool = false) async {
        let householdIds = effectiveViewHouseholdIds
        guard householdIds.isEmpty == false else {
            flexibleTasks = []
            completedTasks = []
            deletedTasks = []
            taskIDsWithAttachments = []
            loadedViewToken = nil
            if !silent {
                errorMessage = AppLocalized.localized(L10n.Family.noGroupIsCurrentlySelected)
            }
            return
        }

        let token = viewToken
        var restoredFromDisk = false
        let hasMemoryTodos =
            flexibleTasks.isEmpty == false
            || completedTasks.isEmpty == false
            || deletedTasks.isEmpty == false

        // 有网也先灌磁盘缓存，避免转菊花空等；force 静默刷新在内存为空时同样回填。
        if hasMemoryTodos == false || (force == false && silent == false) {
            var mergedCache: [FamilyTask] = []
            var seen = Set<UUID>()
            for householdId in householdIds {
                if let cached = await HouseholdLocalCache.loadTasks(for: householdId) {
                    for task in cached where seen.insert(task.id).inserted {
                        mergedCache.append(task)
                    }
                }
            }
            if mergedCache.isEmpty == false {
                applyFlexibleTasks(from: mergedCache, onlyIfChanged: true)
                errorMessage = nil
                restoredFromDisk = true
                loadedViewToken = token
            }
        }

        let primaryId = currentHouseholdId ?? householdIds[0]
        if rosterLoadedForHouseholdId != primaryId {
            await loadHouseholdRosterFromCache(in: primaryId)
        }

        let hasDisplayableTodos =
            flexibleTasks.isEmpty == false
            || completedTasks.isEmpty == false
            || deletedTasks.isEmpty == false
        let showLoading = !silent && hasDisplayableTodos == false
        if showLoading {
            isLoading = true
            errorMessage = nil
        }
        defer {
            if showLoading {
                isLoading = false
            }
        }

        guard await NetworkMonitor.shared.isConnected else {
            if restoredFromDisk || hasDisplayableTodos {
                errorMessage = nil
            }
            #if DEBUG
            print("[TodoListViewModel] loadTasks skipped reason=offline households=\(householdIds.count)")
            #endif
            return
        }

        do {
            if rosterLoadedForHouseholdId != primaryId {
                await loadHouseholdRosterFromNetwork(in: primaryId)
            }
            var merged: [FamilyTask] = []
            var seen = Set<UUID>()
            let service = taskService
            try await withThrowingTaskGroup(of: (UUID, [FamilyTask]).self) { group in
                for householdId in householdIds {
                    group.addTask {
                        (householdId, try await service.fetchTasks(in: householdId))
                    }
                }
                for try await (householdId, batch) in group {
                    let filteredBatch = batch.filter { pendingHardDeletedTaskIDs.contains($0.id) == false }
                    LocalCacheManager.shared.save(filteredBatch, forKey: Self.tasksCacheKey(for: householdId))
                    for task in filteredBatch where seen.insert(task.id).inserted {
                        merged.append(task)
                    }
                }
            }
            applyFlexibleTasks(from: merged, onlyIfChanged: true)
            reconcilePendingHardDeletes(with: merged)
            await refreshAttachmentPresence(for: flexibleTasks + completedTasks + deletedTasks)
            loadedViewToken = token
            if !silent {
                errorMessage = nil
            }
        } catch {
            if !silent, restoredFromDisk == false, hasDisplayableTodos == false {
                errorMessage = error.localizedDescription
            }
        }
    }

    func taskHasAttachments(_ task: FamilyTask) -> Bool {
        task.hasAttachmentURLs || taskIDsWithAttachments.contains(task.id)
    }

    private func refreshAttachmentPresence(for tasks: [FamilyTask]) async {
        let ids = tasks.map(\.id)
        guard ids.isEmpty == false else {
            taskIDsWithAttachments = []
            return
        }
        do {
            let found = try await TaskAttachmentSupabaseSupport.fetchTaskIDsHavingAttachments(taskIDs: ids)
            taskIDsWithAttachments = found
            #if DEBUG
            print("[TodoListViewModel] attachment presence count=\(found.count)/\(ids.count)")
            #endif
        } catch {
            #if DEBUG
            print("[TodoListViewModel] attachment presence fetch failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func applyFlexibleTasks(from allTasks: [FamilyTask], onlyIfChanged: Bool = false) {
        let flexible = allTasks
            .filter(\.isFlexibleTodoCandidate)
            .filter { pendingHardDeletedTaskIDs.contains($0.id) == false }
        let nextCompleted = flexible
            .filter { $0.status == .completed }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
        let nextDeleted = flexible
            .filter { $0.status == .cancelled }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
        let nextOpen = flexible
            .filter { isOpenTodo($0) }
            .sorted { lhs, rhs in
                deadlineSortKey(for: lhs) < deadlineSortKey(for: rhs)
            }
        if onlyIfChanged,
           CacheFirstContent.areTasksEquivalent(flexibleTasks, nextOpen),
           CacheFirstContent.areTasksEquivalent(completedTasks, nextCompleted),
           CacheFirstContent.areTasksEquivalent(deletedTasks, nextDeleted) {
            return
        }
        completedTasks = nextCompleted
        deletedTasks = nextDeleted
        flexibleTasks = nextOpen
    }

    private func reconcilePendingHardDeletes(with fetched: [FamilyTask]) {
        guard pendingHardDeletedTaskIDs.isEmpty == false else { return }
        let present = Set(fetched.map(\.id))
        pendingHardDeletedTaskIDs = pendingHardDeletedTaskIDs.filter { present.contains($0) }
    }

    var hasOpenFlexibleTasks: Bool {
        flexibleTasks.isEmpty == false || overdueTasks.isEmpty == false
    }

    func displayTitle(for task: FamilyTask) -> String {
        TaskDisplayResolver.resolvedTitle(
            for: task,
            profiles: familyProfiles,
            locale: AppSettingsManager.shared.appLocale
        )
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

    // MARK: - Sections

    enum TodoSection: String, CaseIterable, Identifiable {
        case overdue
        case today
        case thisWeek
        case later

        var id: String { rawValue }

        var titleKey: LocalizedStringResource {
            switch self {
            case .overdue: L10n.Common.overdue.localized
            case .today: L10n.Common.dueToday.localized
            case .thisWeek: L10n.Common.dueThisWeek.localized
            case .later: L10n.Common.later.localized
            }
        }
    }

    var overdueTasks: [FamilyTask] {
        let now = Date()
        return flexibleTasks.filter { task in
            guard let end = task.endDatetime else { return false }
            return end < now
        }
    }

    /// 白板左上垃圾桶：过期开放待办 + 已删除（软删）待办。
    var trashBinTasks: [FamilyTask] {
        overdueTasks + deletedTasks
    }

    var trashBinCount: Int {
        trashBinTasks.count
    }

    /// 主列表分区（不含已过期；过期任务从标题下横幅入口查看）。
    func mainSectionedTasks(calendar: Calendar = .current) -> [(TodoSection, [FamilyTask])] {
        sectionedTasks(calendar: calendar, includeOverdue: false)
    }

    /// 便签白板正面：今日 + 本周（近期）。
    func stickyBoardNearTasks(calendar: Calendar = .current) -> [FamilyTask] {
        mainSectionedTasks(calendar: calendar).flatMap { section, items in
            (section == .today || section == .thisWeek) ? items : []
        }
    }

    /// 便签白板背面：更晚 / 无截止日期（远期）。
    func stickyBoardFarTasks(calendar: Calendar = .current) -> [FamilyTask] {
        mainSectionedTasks(calendar: calendar).first(where: { $0.0 == .later })?.1 ?? []
    }

    func sectionedTasks(calendar: Calendar = .current, includeOverdue: Bool = true) -> [(TodoSection, [FamilyTask])] {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) else {
            let items = includeOverdue
                ? flexibleTasks
                : flexibleTasks.filter { !isOverdue($0, now: now) }
            return items.isEmpty ? [] : [(TodoSection.later, items)]
        }

        var buckets: [TodoSection: [FamilyTask]] = [:]
        for task in flexibleTasks {
            if isOverdue(task, now: now) {
                if includeOverdue {
                    buckets[.overdue, default: []].append(task)
                }
                continue
            }
            guard let day = task.flexibleDeadlineDay else {
                buckets[.later, default: []].append(task)
                continue
            }
            if calendar.isDate(day, inSameDayAs: today) {
                buckets[.today, default: []].append(task)
            } else if day < weekEnd {
                buckets[.thisWeek, default: []].append(task)
            } else {
                buckets[.later, default: []].append(task)
            }
        }

        let sections = includeOverdue
            ? TodoSection.allCases
            : TodoSection.allCases.filter { $0 != .overdue }

        return sections.compactMap { section in
            guard let items = buckets[section], items.isEmpty == false else { return nil }
            return (section, items)
        }
    }

    private func isOverdue(_ task: FamilyTask, now: Date) -> Bool {
        guard let end = task.endDatetime else { return false }
        return end < now
    }

    // MARK: - Private

    private func loadHouseholdRosterFromCache(in householdId: UUID) async {
        guard rosterLoadedForHouseholdId != householdId else { return }
        guard let snapshot = await HouseholdLocalCache.loadMembers(for: householdId) else { return }
        let filtered = snapshot.filteredToActiveMembers(in: householdId)
        HouseholdLocalCache.applyRosterSnapshot(
            filtered,
            to: &householdMembers,
            familyProfiles: &familyProfiles
        )
        rosterLoadedForHouseholdId = householdId
    }

    private func loadHouseholdRosterFromNetwork(in householdId: UUID) async {
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
            if rosterLoadedForHouseholdId != householdId {
                householdMembers = []
                familyProfiles = []
            }
        }
    }

    private func isOpenTodo(_ task: FamilyTask) -> Bool {
        switch task.status {
        case .completed, .cancelled, .failed, .expired:
            return false
        default:
            return true
        }
    }

    private func deadlineSortKey(for task: FamilyTask) -> Date {
        task.flexibleDeadlineDay ?? .distantFuture
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

    func applyOptimisticCompletion(for task: FamilyTask) {
        flexibleTasks.removeAll { $0.id == task.id }
        var optimistic = task
        optimistic.status = .completed
        completedTasks.removeAll { $0.id == task.id }
        completedTasks.insert(optimistic, at: 0)
    }

    func applyOptimisticDeletion(for task: FamilyTask) {
        flexibleTasks.removeAll { $0.id == task.id }
        completedTasks.removeAll { $0.id == task.id }
        var optimistic = task
        optimistic.status = .cancelled
        deletedTasks.removeAll { $0.id == optimistic.id }
        deletedTasks.insert(optimistic, at: 0)
        HouseholdLocalCache.upsertTaskInCache(optimistic)
    }

    /// 白板拖入垃圾桶：软删除为 `cancelled`，保留在垃圾桶列表中（非硬删行）。
    func deleteFlexibleTask(_ task: FamilyTask, actingMembershipId: UUID? = nil) async throws {
        applyOptimisticDeletion(for: task)
        await NotificationManager.shared.cancelAllPending(for: task.id)

        if await NetworkMonitor.shared.isConnected == false {
            TaskOfflineOutbox.shared.enqueue(
                .patchStatus(
                    taskId: task.id,
                    status: .cancelled,
                    completionLocation: nil,
                    actingMembershipId: actingMembershipId
                )
            )
            NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            return
        }

        do {
            let updated = try await taskService.patchTaskStatus(
                taskId: task.id,
                to: .cancelled,
                completionLocation: nil,
                actingMembershipId: actingMembershipId
            )
            flexibleTasks.removeAll { $0.id == updated.id }
            completedTasks.removeAll { $0.id == updated.id }
            deletedTasks.removeAll { $0.id == updated.id }
            deletedTasks.insert(updated, at: 0)
            HouseholdLocalCache.upsertTaskInCache(updated)
            NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        } catch {
            if Self.isLikelyNetworkFailure(error) {
                TaskOfflineOutbox.shared.enqueue(
                    .patchStatus(
                        taskId: task.id,
                        status: .cancelled,
                        completionLocation: nil,
                        actingMembershipId: actingMembershipId
                    )
                )
                NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
                return
            }
            await loadTasks(silent: true, force: true)
            throw error
        }
    }

    /// 一键清空垃圾桶：永久删除其中所有过期与已软删待办。
    func clearTrashBin() async throws {
        let targets = trashBinTasks
        guard targets.isEmpty == false else { return }

        let ids = Set(targets.map(\.id))
        pendingHardDeletedTaskIDs.formUnion(ids)
        flexibleTasks.removeAll { ids.contains($0.id) }
        deletedTasks.removeAll { ids.contains($0.id) }
        completedTasks.removeAll { ids.contains($0.id) }

        for task in targets {
            HouseholdLocalCache.removeTaskFromCache(taskId: task.id, householdId: task.householdId)
            await NotificationManager.shared.cancelAllPending(for: task.id)
        }

        if await NetworkMonitor.shared.isConnected == false {
            for task in targets {
                TaskOfflineOutbox.shared.enqueue(.delete(taskId: task.id))
            }
            // 不广播全量刷新，避免其它 VM 立刻拉旧快照覆盖本地缓存。
            return
        }

        var encounteredHardFailure: Error?
        for task in targets {
            do {
                try await taskService.deleteTask(taskId: task.id)
                HouseholdLocalCache.removeTaskFromCache(taskId: task.id, householdId: task.householdId)
            } catch {
                if Self.isLikelyNetworkFailure(error) {
                    TaskOfflineOutbox.shared.enqueue(.delete(taskId: task.id))
                } else {
                    encounteredHardFailure = error
                }
            }
        }

        // 静默对齐一次；pendingHardDeletedTaskIDs 会挡住删后仍短暂返回的行。
        await loadTasks(silent: true, force: true)

        if let encounteredHardFailure {
            throw encounteredHardFailure
        }
    }

    func completeFlexibleTask(_ task: FamilyTask, actingMembershipId: UUID?) async throws {
        var optimistic = task
        optimistic.status = .completed
        flexibleTasks.removeAll { $0.id == optimistic.id }
        completedTasks.removeAll { $0.id == optimistic.id }
        completedTasks.insert(optimistic, at: 0)
        HouseholdLocalCache.upsertTaskInCache(optimistic)

        if await NetworkMonitor.shared.isConnected == false {
            TaskOfflineOutbox.shared.enqueue(
                .patchStatus(
                    taskId: task.id,
                    status: .completed,
                    completionLocation: nil,
                    actingMembershipId: actingMembershipId
                )
            )
            AnalyticsManager.logTaskCompleted(
                taskId: task.id,
                householdId: task.householdId,
                taskType: AnalyticsManager.analyticsTaskType(for: task)
            )
            NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            return
        }

        do {
            let updated = try await taskService.patchTaskStatus(
                taskId: task.id,
                to: .completed,
                completionLocation: nil,
                actingMembershipId: actingMembershipId
            )
            flexibleTasks.removeAll { $0.id == updated.id }
            completedTasks.removeAll { $0.id == updated.id }
            completedTasks.insert(updated, at: 0)
            HouseholdLocalCache.upsertTaskInCache(updated)
            AnalyticsManager.logTaskCompleted(
                taskId: updated.id,
                householdId: updated.householdId,
                taskType: AnalyticsManager.analyticsTaskType(for: updated)
            )
            NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        } catch {
            if Self.isLikelyNetworkFailure(error) {
                TaskOfflineOutbox.shared.enqueue(
                    .patchStatus(
                        taskId: task.id,
                        status: .completed,
                        completionLocation: nil,
                        actingMembershipId: actingMembershipId
                    )
                )
                NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
                return
            }
            throw error
        }
    }

    private static func isLikelyNetworkFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return true }
        let text = error.localizedDescription.lowercased()
        return text.contains("network")
            || text.contains("offline")
            || text.contains("timed out")
            || text.contains("internet")
    }
}
