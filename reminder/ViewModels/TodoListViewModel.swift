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
    @Published private(set) var householdMembers: [HouseholdMembership] = []
    @Published private(set) var familyProfiles: [FamilyProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let taskService: TaskDataService
    private let membershipService: HouseholdMembershipDataService
    private let familyProfileService: FamilyProfileDataService
    private var currentHouseholdId: UUID?
    private var rosterLoadedForHouseholdId: UUID?
    /// 当前群组是否已有内存数据；切 Tab 回来时不重复拉网。
    private var loadedHouseholdId: UUID?
    private var reloadCancellable: AnyCancellable?

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
            householdMembers = []
            familyProfiles = []
            rosterLoadedForHouseholdId = nil
            loadedHouseholdId = nil
        } else if householdChanged {
            loadedHouseholdId = nil
            if rosterLoadedForHouseholdId != householdId {
                rosterLoadedForHouseholdId = nil
            }
        }
    }

    private static func tasksCacheKey(for householdId: UUID) -> String {
        "schedule.tasks.snapshot.\(householdId.uuidString.lowercased())"
    }

    /// 首次进入或切换群组时加载；已有内存缓存则跳过网络请求。
    func loadTasksIfNeeded() async {
        guard let householdId = currentHouseholdId else {
            flexibleTasks = []
            completedTasks = []
            errorMessage = AppLocalized.localized("当前未选择群组。")
            return
        }

        if loadedHouseholdId == householdId {
            return
        }

        await loadTasks(silent: false)
    }

    func loadTasks(silent: Bool = false, force: Bool = false) async {
        guard let householdId = currentHouseholdId else {
            flexibleTasks = []
            completedTasks = []
            loadedHouseholdId = nil
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
        if force == false, silent == false,
           let cached: [FamilyTask] = LocalCacheManager.shared.load(forKey: cacheKey) {
            applyFlexibleTasks(from: cached)
            errorMessage = nil
            restoredFromDisk = true
            loadedHouseholdId = householdId
        }

        let showLoading = !silent && !restoredFromDisk && flexibleTasks.isEmpty
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
            let fresh = try await taskService.fetchTasks(in: householdId)
            applyFlexibleTasks(from: fresh)
            LocalCacheManager.shared.save(fresh, forKey: cacheKey)
            loadedHouseholdId = householdId
            if !silent {
                errorMessage = nil
            }
        } catch {
            if !silent, restoredFromDisk == false {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyFlexibleTasks(from allTasks: [FamilyTask]) {
        let flexible = allTasks.filter(\.isFlexibleTodo)
        completedTasks = flexible
            .filter { $0.status == .completed }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
        flexibleTasks = flexible
            .filter { isOpenTodo($0) }
            .sorted { lhs, rhs in
                deadlineSortKey(for: lhs) < deadlineSortKey(for: rhs)
            }
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

        var titleKey: LocalizedStringKey {
            switch self {
            case .overdue: "已逾期"
            case .today: "今天截止"
            case .thisWeek: "本周截止"
            case .later: "以后"
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

    /// 主列表分区（不含已过期；过期任务从标题下横幅入口查看）。
    func mainSectionedTasks(calendar: Calendar = .current) -> [(TodoSection, [FamilyTask])] {
        sectionedTasks(calendar: calendar, includeOverdue: false)
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
}
