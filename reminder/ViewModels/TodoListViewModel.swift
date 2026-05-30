import Foundation
import Combine
import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class TodoListViewModel: ObservableObject {
    @Published private(set) var flexibleTasks: [FamilyTask] = []
    @Published private(set) var householdMembers: [HouseholdMembership] = []
    @Published private(set) var familyProfiles: [FamilyProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let taskService: TaskDataService
    private let membershipService: HouseholdMembershipDataService
    private let familyProfileService: FamilyProfileDataService
    private var currentHouseholdId: UUID?
    private var rosterLoadedForHouseholdId: UUID?
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
                    await self?.loadTasks(silent: true)
                }
            }
    }

    func setHouseholdContext(_ householdId: UUID?) {
        currentHouseholdId = householdId
        if householdId == nil {
            flexibleTasks = []
            householdMembers = []
            familyProfiles = []
            rosterLoadedForHouseholdId = nil
        } else if rosterLoadedForHouseholdId != householdId {
            rosterLoadedForHouseholdId = nil
        }
    }

    func loadTasks(silent: Bool = false) async {
        guard let householdId = currentHouseholdId else {
            flexibleTasks = []
            if !silent {
                errorMessage = AppLocalized.localized("当前未选择群组。")
            }
            return
        }

        if rosterLoadedForHouseholdId != householdId {
            await loadHouseholdRoster(in: householdId)
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
            let fresh = try await taskService.fetchTasks(in: householdId)
            flexibleTasks = fresh
                .filter(\.isFlexibleTodo)
                .filter { isOpenTodo($0) }
                .sorted { lhs, rhs in
                    deadlineSortKey(for: lhs) < deadlineSortKey(for: rhs)
                }
            errorMessage = nil
        } catch {
            if !silent {
                errorMessage = error.localizedDescription
            }
        }
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

    func sectionedTasks(calendar: Calendar = .current) -> [(TodoSection, [FamilyTask])] {
        let today = calendar.startOfDay(for: Date())
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) else {
            return [(TodoSection.later, flexibleTasks)]
        }

        var buckets: [TodoSection: [FamilyTask]] = [:]
        for task in flexibleTasks {
            guard let day = task.flexibleDeadlineDay else {
                buckets[.later, default: []].append(task)
                continue
            }
            if day < today {
                buckets[.overdue, default: []].append(task)
            } else if calendar.isDate(day, inSameDayAs: today) {
                buckets[.today, default: []].append(task)
            } else if day < weekEnd {
                buckets[.thisWeek, default: []].append(task)
            } else {
                buckets[.later, default: []].append(task)
            }
        }

        return TodoSection.allCases.compactMap { section in
            guard let items = buckets[section], items.isEmpty == false else { return nil }
            return (section, items)
        }
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
