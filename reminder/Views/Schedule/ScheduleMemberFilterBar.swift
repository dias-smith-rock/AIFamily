import SwiftUI

/// 日程日历上方的家庭成员头像筛选条：点击切换选中，选中者相关任务才会显示。
struct ScheduleMemberFilterBar: View {
    let members: [HouseholdMembership]
    let profiles: [FamilyProfile]
    let selectedIds: Set<UUID>
    let onToggle: (UUID) -> Void

    var body: some View {
        if members.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(members) { member in
                        memberButton(for: member)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func memberButton(for member: HouseholdMembership) -> some View {
        let isSelected = selectedIds.contains(member.id)
        let profile = MemberDisplayName.profile(for: member, in: profiles)
        let name = MemberDisplayName.displayName(for: member, profiles: profiles)
        let avatarURL = profile?.avatarUrl.flatMap { URL(string: $0) }

        return Button {
            onToggle(member.id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                LocationMemberAvatarView(
                    displayName: name,
                    avatarURL: avatarURL,
                    size: 40,
                    isGrayscale: isSelected == false
                )
                .opacity(isSelected ? 1 : 0.55)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? AppTheme.ColorToken.accent.opacity(0.9) : Color.clear,
                            lineWidth: 2
                        )
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.green)
                        .background(Circle().fill(Color.black.opacity(0.15)).padding(1))
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
