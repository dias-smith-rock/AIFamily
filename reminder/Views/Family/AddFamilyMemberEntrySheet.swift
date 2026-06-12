import SwiftUI

/// 添加群组成员入口：邀请制 vs 新建档案成员（尚无 membership）。
struct AddFamilyMemberEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    let canCreateProfileWithoutAccount: Bool
    let onChooseInvite: () -> Void
    let onChooseCreateProfile: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onChooseInvite()
                    } label: {
                        entryRow(
                            icon: "paperplane.fill",
                            title: L10n.Family.inviteMembersToJoin.localized,
                            subtitle: L10n.Auth.sendAnInviteLinkSoTheyCanSignInOnTheir.localized
                        )
                    }
                    .buttonStyle(.plain)

                    if canCreateProfileWithoutAccount {
                        Button {
                            onChooseCreateProfile()
                        } label: {
                            entryRow(
                                icon: "person.text.rectangle",
                                title: L10n.Family.createMemberProfile.localized,
                                subtitle: L10n.Schedule.noPhoneNumberNeededYouCanRecordTasksOnT.localized
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(L10n.Family.addGroupMembers.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close.localized) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func entryRow(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

#Preview {
    AddFamilyMemberEntrySheet(
        canCreateProfileWithoutAccount: true,
        onChooseInvite: {},
        onChooseCreateProfile: {}
    )
}
