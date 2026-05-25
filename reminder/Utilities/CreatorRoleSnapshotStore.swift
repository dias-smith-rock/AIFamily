import Foundation

#if canImport(Supabase)
import Supabase
#endif

/// UserDefaults 快照：检测「他人转移创建者权限」并避免首次登录 / 自建家庭误弹窗。
enum CreatorRoleSnapshotStore {
    static func cacheKey(for userId: UUID) -> String {
        "known_creator_ids_\(userId.uuidString.lowercased())"
    }

    static func currentUserId() async -> UUID? {
        #if canImport(Supabase)
        return try? await SupabaseManager.shared.client.auth.session.user.id
        #else
        return nil
        #endif
    }

    @MainActor
    static func markKnownCreatorHousehold(_ householdId: UUID, userId: UUID) {
        let key = cacheKey(for: userId)
        var knownIds = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        let idString = householdId.uuidString.lowercased()
        guard knownIds.contains(idString) == false else { return }
        knownIds.append(idString)
        UserDefaults.standard.set(knownIds, forKey: key)
    }

    @MainActor
    static func markKnownCreatorHouseholdIfPossible(_ householdId: UUID) async {
        guard let userId = await currentUserId() else { return }
        markKnownCreatorHousehold(householdId, userId: userId)
    }

    /// 返回应弹窗的新创建者家庭；`nil` 表示无需弹窗。
    @MainActor
    static func newlyAssignedCreatorHousehold(
        in fetchedHouseholds: [JoinedHousehold],
        userId: UUID
    ) -> JoinedHousehold? {
        let currentCreatorHouseholds = fetchedHouseholds.filter {
            $0.normalizedRole == MembershipRole.creator.rawValue
        }
        let currentCreatorIds = currentCreatorHouseholds.map { $0.householdId.uuidString.lowercased() }
        let key = cacheKey(for: userId)

        let previouslyKnown = UserDefaults.standard.array(forKey: key) as? [String]

        if previouslyKnown == nil {
            UserDefaults.standard.set(currentCreatorIds, forKey: key)
            return nil
        }

        let knownIds = previouslyKnown ?? []
        defer {
            UserDefaults.standard.set(currentCreatorIds, forKey: key)
        }

        guard let newId = currentCreatorIds.first(where: { knownIds.contains($0) == false }),
              let newHousehold = currentCreatorHouseholds.first(where: {
                  $0.householdId.uuidString.lowercased() == newId
              }) else {
            return nil
        }

        return newHousehold
    }
}
