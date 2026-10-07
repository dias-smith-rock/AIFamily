import Foundation

/// 成员展示名解析：千组织千面 — 有 membership 用 `nickname`，无 membership 用 `family_profiles.name`。
enum MemberDisplayName {
    static var unknownFallback: String {
        AppLocalized.localizedSync(L10n.Family.unknownMember)
    }

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
        nonEmpty(resolvedGuestSelfName(membership.displayName(linkedProfile: profile(for: membership, in: profiles))))
    }

    static func displayName(
        forMembershipId membershipId: UUID,
        members: [HouseholdMembership],
        profiles: [FamilyProfile]
    ) -> String? {
        guard let membership = members.first(where: { $0.id == membershipId }) else { return nil }
        return displayName(for: membership, profiles: profiles)
    }

    /// 列表行展示名：优先嵌套数组内 nickname，否则档案 `name`。
    static func displayName(for profile: FamilyProfile, membership: HouseholdMembership? = nil) -> String {
        if let membership {
            return nonEmpty(membership.displayName(linkedProfile: profile))
        }
        return nonEmpty(profile.displayName)
    }

    /// 去掉空白与零宽字符后若仍为空，回退「未知成员」。
    static func nonEmpty(_ raw: String?) -> String {
        let trimmed = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unknownFallback : trimmed
    }

    private static func resolvedGuestSelfName(_ raw: String) -> String {
        return StoredDisplayNameResolver.selfName(raw)
    }
}
