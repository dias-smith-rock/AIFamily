import Foundation

/// 将 AI 识图返回的 `participant_hints` 与当前群组档案/成员昵称做模糊匹配。
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

        let everyoneHints = ["全班", "全家", "所有人", "每位", "all", "everyone", "whole family"]
        if normalizedHints.contains(where: { hint in
            everyoneHints.contains { hint.contains(normalize($0)) || normalize($0).contains(hint) }
        }) {
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
