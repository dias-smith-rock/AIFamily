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

    static func loadMembers(for householdId: UUID) async -> MembersSnapshot? {
        await LocalCacheManager.shared.load(forKey: membersCacheKey(for: householdId))
    }

    static func loadTasks(for householdId: UUID) async -> [FamilyTask]? {
        await LocalCacheManager.shared.load(forKey: tasksCacheKey(for: householdId))
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
