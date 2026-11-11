import Foundation

/// 任务/待办「是否可编辑」——与线上 `tasks` UPDATE RLS 的 WITH CHECK 对齐：
/// 群组 creator/admin，或当前 membership 为 `tasks.creator_id`。
/// （`creator_id` / membership 均为 `household_memberships.id`，禁止用 `auth.users.id`。）
enum TaskEditAccess {
    static func canEdit(
        _ task: FamilyTask,
        membershipId: UUID?,
        role: MembershipRole?
    ) -> Bool {
        guard task.source.isReadOnly == false else { return false }
        if let membershipId, membershipId == task.creatorId {
            return true
        }
        switch role {
        case .creator, .admin:
            return true
        case .member, .none:
            return false
        }
    }

    static func role(
        of membershipId: UUID?,
        in members: [HouseholdMembership]
    ) -> MembershipRole? {
        guard let membershipId else { return nil }
        return members.first(where: { $0.id == membershipId })?.parsedRole
    }
}
