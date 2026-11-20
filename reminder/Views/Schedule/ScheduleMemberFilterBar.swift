import SwiftUI

/// 日程成员筛选条中的一项：正式 membership 或无账号虚拟档案。
struct ScheduleFilterMember: Identifiable, Equatable {
    /// 筛选态 id：正式成员用 membership id，虚拟成员用 profile id。
    let id: UUID
    let membershipId: UUID?
    let profileId: UUID?
    let displayName: String
    let avatarURL: URL?
    let isVirtual: Bool
}

/// 日程日历上方的家庭成员头像筛选条：点击切换选中，选中者相关任务才会显示。
struct ScheduleMemberFilterBar: View {
    let members: [ScheduleFilterMember]
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

    private func memberButton(for member: ScheduleFilterMember) -> some View {
        let isSelected = selectedIds.contains(member.id)

        return Button {
            onToggle(member.id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                LocationMemberAvatarView(
                    displayName: member.displayName,
                    avatarURL: member.avatarURL,
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
        .accessibilityLabel(member.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
