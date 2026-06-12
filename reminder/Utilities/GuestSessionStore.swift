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
    /// String Catalog Key；游客默认群组名持久化用此固定键，展示时按当前语言解析。
    static let defaultHouseholdNameCatalogKey = L10n.Common.mySpace.key
    /// String Catalog Key；游客默认自称（档案名 / nickname）持久化用此固定键。
    static let defaultSelfDisplayNameCatalogKey = L10n.Common.me.key

    /// 游客位置 Tab 演示用虚拟成员（稳定 ID，便于与模拟坐标对齐）。
    static let locationDemoProfile1Id = UUID(uuidString: "D1000001-0000-4000-8000-000000000001") ?? UUID()
    static let locationDemoProfile2Id = UUID(uuidString: "D1000002-0000-4000-8000-000000000002") ?? UUID()
    static let locationDemoProfile1NameKey = "Alex"
    static let locationDemoProfile2NameKey = "Jordan"

    static func locationDemoProfiles(householdId: UUID) -> [FamilyProfile] {
        [
            FamilyProfile(
                id: locationDemoProfile1Id,
                householdId: householdId,
                name: locationDemoProfile1NameKey,
                userId: nil
            ),
            FamilyProfile(
                id: locationDemoProfile2Id,
                householdId: householdId,
                name: locationDemoProfile2NameKey,
                userId: nil
            ),
        ]
    }

    static func isLocationDemoProfileId(_ profileId: UUID) -> Bool {
        profileId == locationDemoProfile1Id || profileId == locationDemoProfile2Id
    }

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

    static func isDefaultGuestHouseholdName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) == defaultHouseholdNameCatalogKey
    }

    static func localizedDefaultHouseholdName() -> String {
        AppLocalized.localizedSync(L10n.Common.mySpace)
    }

    /// 游客默认群组名按当前语言展示；用户自定义名称原样返回。
    static func displayHouseholdName(_ storedName: String?) -> String {
        let trimmed = storedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return trimmed }
        guard isGuestMode, isDefaultGuestHouseholdName(trimmed) else { return trimmed }
        return localizedDefaultHouseholdName()
    }

    static func isDefaultGuestSelfDisplayName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) == defaultSelfDisplayNameCatalogKey
    }

    static func localizedDefaultSelfDisplayName() -> String {
        AppLocalized.localizedSync(L10n.Common.me)
    }

    /// 游客默认自称按当前语言展示；用户自定义名称原样返回。
    static func displaySelfName(_ storedName: String?) -> String {
        let trimmed = storedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return trimmed }
        guard isGuestMode, isDefaultGuestSelfDisplayName(trimmed) else { return trimmed }
        return localizedDefaultSelfDisplayName()
    }

    /// 迁移写入云端时将默认自称解析为当前语言。
    static func cloudMigrationSelfName(_ storedName: String) -> String {
        let trimmed = storedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isDefaultGuestSelfDisplayName(trimmed) else { return trimmed }
        return localizedDefaultSelfDisplayName()
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
            nickname: defaultSelfDisplayNameCatalogKey,
            status: MembershipStatus.active.rawValue,
            joinedAt: now,
            createdAt: now,
            updatedAt: now
        )
        var profile = FamilyProfile(
            id: profileId,
            householdId: nil,
            name: defaultSelfDisplayNameCatalogKey,
            userId: nil
        )
        profile.householdMemberships = [membership]

        return GuestWorkspaceSnapshot(
            householdId: householdId,
            membershipId: membershipId,
            profileId: profileId,
            householdName: defaultHouseholdNameCatalogKey,
            householdDescription: "",
            tasks: [],
            profiles: [profile] + locationDemoProfiles(householdId: householdId),
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
