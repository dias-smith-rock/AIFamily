import Foundation

/// 群组相关磁盘快照（成员名册、任务列表）的键与读取。
enum HouseholdLocalCache {
    struct MembersSnapshot: Codable, Sendable {
        let profiles: [FamilyProfile]
        let members: [HouseholdMembership]

        func filteredToActiveMembers(in householdId: UUID) -> MembersSnapshot {
            let roster = HouseholdMemberRoster(profiles: profiles, memberships: members)
                .filteredToActiveMembers(in: householdId)
            return MembersSnapshot(profiles: roster.profiles, members: roster.memberships)
        }
    }

    static func membersCacheKey(for householdId: UUID) -> String {
        "family.members.snapshot.\(householdId.uuidString.lowercased())"
    }

    static func tasksCacheKey(for householdId: UUID) -> String {
        "schedule.tasks.snapshot.\(householdId.uuidString.lowercased())"
    }

    static func locationStatesCacheKey(for householdId: UUID) -> String {
        "location.states.snapshot.\(householdId.uuidString.lowercased())"
    }

    static func listsCacheKey(for householdId: UUID) -> String {
        "planner.lists.snapshot.\(householdId.uuidString.lowercased())"
    }

    static func listItemsCacheKey(for listId: UUID) -> String {
        "planner.list_items.snapshot.\(listId.uuidString.lowercased())"
    }

    static func loadMembers(for householdId: UUID) async -> MembersSnapshot? {
        await LocalCacheManager.shared.load(forKey: membersCacheKey(for: householdId))
    }

    static func loadTasks(for householdId: UUID) async -> [FamilyTask]? {
        await LocalCacheManager.shared.load(forKey: tasksCacheKey(for: householdId))
    }

    static func saveTasks(_ tasks: [FamilyTask], for householdId: UUID) {
        LocalCacheManager.shared.save(tasks, forKey: tasksCacheKey(for: householdId))
    }

    /// 将单条任务合并进对应家庭的磁盘快照（离线乐观写）。
    static func upsertTaskInCache(_ task: FamilyTask) {
        let key = tasksCacheKey(for: task.householdId)
        var cached: [FamilyTask] = LocalCacheManager.shared.load(forKey: key) ?? []
        if let index = cached.firstIndex(where: { $0.id == task.id }) {
            cached[index] = task
        } else {
            cached.append(task)
        }
        LocalCacheManager.shared.save(cached, forKey: key)
    }

    static func removeTaskFromCache(taskId: UUID, householdId: UUID) {
        let key = tasksCacheKey(for: householdId)
        var cached: [FamilyTask] = LocalCacheManager.shared.load(forKey: key) ?? []
        cached.removeAll { $0.id == taskId }
        LocalCacheManager.shared.save(cached, forKey: key)
    }

    /// RPC 创建后服务端 id 与本地临时 id 不一致时，替换缓存行。
    static func replaceTask(fromId: UUID, with task: FamilyTask) {
        let key = tasksCacheKey(for: task.householdId)
        var cached: [FamilyTask] = LocalCacheManager.shared.load(forKey: key) ?? []
        cached.removeAll { $0.id == fromId || $0.id == task.id }
        cached.append(task)
        LocalCacheManager.shared.save(cached, forKey: key)
    }

    static func loadLists(for householdId: UUID) async -> [HouseholdList]? {
        await LocalCacheManager.shared.load(forKey: listsCacheKey(for: householdId))
    }

    static func saveLists(_ lists: [HouseholdList], for householdId: UUID) {
        LocalCacheManager.shared.save(lists, forKey: listsCacheKey(for: householdId))
    }

    static func upsertListInCache(_ list: HouseholdList) {
        let key = listsCacheKey(for: list.householdId)
        var cached: [HouseholdList] = LocalCacheManager.shared.load(forKey: key) ?? []
        if let index = cached.firstIndex(where: { $0.id == list.id }) {
            cached[index] = list
        } else {
            cached.insert(list, at: 0)
        }
        LocalCacheManager.shared.save(cached, forKey: key)
    }

    static func removeListFromCache(listId: UUID, householdId: UUID) {
        let key = listsCacheKey(for: householdId)
        var cached: [HouseholdList] = LocalCacheManager.shared.load(forKey: key) ?? []
        cached.removeAll { $0.id == listId }
        LocalCacheManager.shared.save(cached, forKey: key)
        LocalCacheManager.shared.remove(forKey: listItemsCacheKey(for: listId))
    }

    static func loadListItems(for listId: UUID) async -> [ListItem]? {
        await LocalCacheManager.shared.load(forKey: listItemsCacheKey(for: listId))
    }

    static func saveListItems(_ items: [ListItem], for listId: UUID) {
        LocalCacheManager.shared.save(items, forKey: listItemsCacheKey(for: listId))
    }

    static func upsertListItemInCache(_ item: ListItem) {
        let key = listItemsCacheKey(for: item.listId)
        var cached: [ListItem] = LocalCacheManager.shared.load(forKey: key) ?? []
        if let index = cached.firstIndex(where: { $0.id == item.id }) {
            cached[index] = item
        } else {
            cached.append(item)
        }
        LocalCacheManager.shared.save(cached, forKey: key)
    }

    static func removeListItemFromCache(itemId: UUID, listId: UUID) {
        let key = listItemsCacheKey(for: listId)
        var cached: [ListItem] = LocalCacheManager.shared.load(forKey: key) ?? []
        cached.removeAll { $0.id == itemId }
        LocalCacheManager.shared.save(cached, forKey: key)
    }

    static func loadLocationStates(for householdId: UUID) async -> [LocationStateRecord]? {
        await LocalCacheManager.shared.load(forKey: locationStatesCacheKey(for: householdId))
    }

    static func saveLocationStates(_ records: [LocationStateRecord], for householdId: UUID) {
        LocalCacheManager.shared.save(records, forKey: locationStatesCacheKey(for: householdId))
    }

    /// 将缓存名册写入日程/待办 VM 的 `householdMembers` / `familyProfiles`。
    /// 离线时从成员快照解析当前 membership 角色，避免为 `role` 单独请求 Supabase。
    static func membershipRole(for membershipId: UUID, in householdId: UUID) async -> MembershipRole? {
        guard let snapshot = await loadMembers(for: householdId) else { return nil }
        let filtered = snapshot.filteredToActiveMembers(in: householdId)
        if let match = filtered.members.first(where: { $0.id == membershipId }) {
            return match.parsedRole
        }
        let embedded = FamilyProfile.uniqueMembershipsFlattened(from: filtered.profiles)
        return embedded.first(where: { $0.id == membershipId })?.parsedRole
    }

    static func applyRosterSnapshot(
        _ snapshot: MembersSnapshot,
        to householdMembers: inout [HouseholdMembership],
        familyProfiles: inout [FamilyProfile]
    ) {
        familyProfiles = snapshot.profiles
        let embedded = FamilyProfile.uniqueMembershipsFlattened(from: snapshot.profiles)
        let embeddedIds = Set(embedded.map(\.id))
        let orphans = snapshot.members.filter { embeddedIds.contains($0.id) == false }
        let merged = embedded + orphans
        householdMembers = merged
            .filter { $0.isActiveMembership() }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
