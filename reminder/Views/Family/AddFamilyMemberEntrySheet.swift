import SwiftUI

/// 添加家庭成员入口：邀请制 vs 新建档案成员（尚无 membership）。
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
                            title: "邀请家人加入",
                            subtitle: "发送邀请链接，家人可使用自己的手机登录并互动。"
                        )
                    }
                    .buttonStyle(.plain)

                    if canCreateProfileWithoutAccount {
                        Button {
                            onChooseCreateProfile()
                        } label: {
                            entryRow(
                                icon: "person.text.rectangle",
                                title: "创建成员档案",
                                subtitle: "无需手机号，由您直接替 Ta 记录任务（适合小孩子或长辈）。"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("添加家庭成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func entryRow(icon: String, title: String, subtitle: String) -> some View {
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
