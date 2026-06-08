import Foundation

/// 游客工作区快照：任务、名册与合成组织 ID 均仅存本机。
struct GuestWorkspaceSnapshot: Codable, Equatable, Sendable {
    let householdId: UUID
    let membershipId: UUID
    let profileId: UUID
    var householdName: String
    var householdDescription: String
    var tasks: [FamilyTask]
    var profiles: [FamilyProfile]
    var memberships: [HouseholdMembership]
    let createdAt: Date
}

enum GuestSessionStore {
    static let snapshotCacheKey = "guest.workspace.snapshot"
    static let isGuestModeKey = "isGuestMode"

    static var isGuestMode: Bool {
        UserDefaults.standard.bool(forKey: isGuestModeKey)
    }

    static func setGuestMode(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: isGuestModeKey)
    }

    static var hasPendingSnapshot: Bool {
        loadSnapshot() != nil
    }

    @discardableResult
    static func loadOrCreate() -> GuestWorkspaceSnapshot {
        if let existing = loadSnapshot() {
            return existing
        }
        let snapshot = makeDefaultSnapshot()
        save(snapshot)
        return snapshot
    }

    static func loadSnapshot() -> GuestWorkspaceSnapshot? {
        LocalCacheManager.shared.load(forKey: snapshotCacheKey)
    }

    static func save(_ snapshot: GuestWorkspaceSnapshot) {
        LocalCacheManager.shared.save(snapshot, forKey: snapshotCacheKey)
    }

    static func clear() {
        LocalCacheManager.shared.remove(forKey: snapshotCacheKey)
        setGuestMode(false)
    }

    static func makeDefaultSnapshot() -> GuestWorkspaceSnapshot {
        let now = Date()
        let householdId = UUID()
        let membershipId = UUID()
        let profileId = UUID()
        let membership = HouseholdMembership(
            id: membershipId,
            householdId: householdId,
            userId: nil,
            profileId: profileId,
            role: MembershipRole.creator.rawValue,
            nickname: "我",
            status: MembershipStatus.active.rawValue,
            joinedAt: now,
            createdAt: now,
            updatedAt: now
        )
        var profile = FamilyProfile(
            id: profileId,
            householdId: nil,
            name: "我",
            userId: nil
        )
        profile.householdMemberships = [membership]

        return GuestWorkspaceSnapshot(
            householdId: householdId,
            membershipId: membershipId,
            profileId: profileId,
            householdName: "我的空间",
            householdDescription: "",
            tasks: [],
            profiles: [profile],
            memberships: [membership],
            createdAt: now
        )
    }
}

@MainActor
enum GuestSessionExit {
    static func signOut(appRouter: AppRouter, appBootstrap: AppBootstrap) {
        GuestSessionStore.clear()
        appBootstrap.exitGuestMode()
        appRouter.exitGuestMode()
    }
}
