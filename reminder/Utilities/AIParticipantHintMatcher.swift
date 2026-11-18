import Foundation

/// 仅将唯一、完整匹配的成员名称用于自动预填；歧义名称由表单提示核对。
enum AIParticipantHintMatcher {
    struct MatchResult: Sendable, Equatable {
        var assigneeMembershipIds: Set<UUID> = []
        var targetProfileIds: Set<UUID> = []
    }

    static func match(
        hints: [String],
        profiles: [FamilyProfile],
        memberships: [HouseholdMembership]
    ) -> MatchResult {
        let normalizedHints = hints
            .map { normalize($0) }
            .filter { $0.isEmpty == false }

        guard normalizedHints.isEmpty == false else { return MatchResult() }

        var result = MatchResult()
        let mergedProfiles = FamilyProfile.mergingMembershipRows(profiles, memberships: memberships)

        for hint in normalizedHints {
            let matches = mergedProfiles.filter { profile in
                searchableTokens(for: profile).contains(hint)
            }
            // A name shared by two people is a suggestion, never an assignment.
            guard matches.count == 1, let profile = matches.first else { continue }
            result.targetProfileIds.insert(profile.id)
            if let membershipId = profile.primaryMembership?.id {
                result.assigneeMembershipIds.insert(membershipId)
            }
        }

        let everyoneHints = Set(["全班", "全家", "全家人", "所有人", "所有成员", "每位", "all", "everyone", "whole family", "all family members"].map(normalize))
        if normalizedHints.contains(where: everyoneHints.contains) {
            result.assigneeMembershipIds = []
            result.targetProfileIds = []
        }

        return result
    }

    private static func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private static func searchableTokens(for profile: FamilyProfile) -> [String] {
        var tokens: [String] = []
        let display = normalize(profile.displayName)
        if display.isEmpty == false { tokens.append(display) }

        if let membership = profile.primaryMembership,
           let nickname = membership.nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
           nickname.isEmpty == false {
            tokens.append(normalize(nickname))
        }

        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty == false {
            tokens.append(normalize(name))
        }

        return Array(Set(tokens))
    }
}
