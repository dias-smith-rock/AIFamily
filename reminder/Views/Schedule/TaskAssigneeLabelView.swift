import SwiftUI

/// 「谁去办」展示：成员名为动态文案；「所有人」等走 String Catalog。
struct TaskAssigneeLabelView: View {
    let task: FamilyTask
    let members: [HouseholdMembership]
    let profiles: [FamilyProfile]
    let fallback: String

    var body: some View {
        if task.involvesWholeHousehold {
            Text("所有人")
        } else if let ids = task.involvedMemberIds, ids.isEmpty == false {
            assigneeText(for: ids)
        } else {
            Text("所有人")
        }
    }

    @ViewBuilder
    private func assigneeText(for ids: [UUID]) -> some View {
        let names = ids.compactMap { id in
            MemberDisplayName.displayName(
                forMembershipId: id,
                members: members,
                profiles: profiles
            )
        }

        if names.isEmpty {
            if ids.count == 1 {
                Text("成员")
            } else {
                Text("\(ids.count) 人")
            }
        } else {
            Text(verbatim: names.joined(separator: ", "))
        }
    }
}
