import Foundation

/// 权限转移候选成员：绑定了真实账号的活跃组织成员。
struct FamilyMember: Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let nickname: String
    let avatarUrl: String?

    static func from(membership: HouseholdMembership, profile: FamilyProfile?) -> FamilyMember? {
        guard let userId = membership.userId else { return nil }
        let trimmedNickname = membership.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname: String
        if let trimmedNickname, trimmedNickname.isEmpty == false {
            nickname = trimmedNickname
        } else if let profile {
            nickname = profile.displayName
        } else {
            nickname = "成员"
        }
        return FamilyMember(
            id: membership.id,
            userId: userId,
            nickname: nickname,
            avatarUrl: profile?.avatarUrl
        )
    }
}
