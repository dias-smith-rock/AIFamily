import Foundation

/// 成员展示名解析：千组织千面 — 有 membership 用 `nickname`，无 membership 用 `family_profiles.name`。
enum MemberDisplayName {
    static let unknownFallback = "未知成员"

    static func profile(
        for membership: HouseholdMembership,
        in profiles: [FamilyProfile]
    ) -> FamilyProfile? {
        if let profileId = membership.profileId,
           let match = profiles.first(where: { $0.id == profileId }) {
            return match
        }
        if let userId = membership.userId {
            return profiles.first {
                $0.householdId == membership.householdId && $0.userId == userId
            }
        }
        return nil
    }

    static func displayName(
        for membership: HouseholdMembership,
        profiles: [FamilyProfile]
    ) -> String {
        membership.displayName(linkedProfile: profile(for: membership, in: profiles))
    }

    static func displayName(
        forMembershipId membershipId: UUID,
        members: [HouseholdMembership],
        profiles: [FamilyProfile]
    ) -> String? {
        guard let membership = members.first(where: { $0.id == membershipId }) else { return nil }
        return displayName(for: membership, profiles: profiles)
    }

    /// 列表行展示名：有 membership 时优先 `nickname`（非空），否则 `family_profiles.name`。
    static func displayName(for profile: FamilyProfile, membership: HouseholdMembership?) -> String {
        let resolvedMembership = membership ?? profile.primaryMembership
        if let resolvedMembership {
            let nickname = resolvedMembership.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if nickname.isEmpty == false {
                return nickname
            }
        }
        if let profileName = profile.profileName {
            return profileName
        }
        return unknownFallback
    }
}
