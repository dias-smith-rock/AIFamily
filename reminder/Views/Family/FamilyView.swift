import SwiftUI

struct FamilyView: View {
    @StateObject private var viewModel = AppViewModels.makeFamilyViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    inviteButton
                    memberSection
                    quickSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadMembers()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("家庭成员")
                .font(.system(size: 40, weight: .bold))
            Text("管理成员与权限")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var inviteButton: some View {
        VStack(spacing: 8) {
            Button {
            } label: {
                Label("邀请新成员", systemImage: "person.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [.blue.opacity(0.8), .blue], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Text("支持微信/WhatsApp免安装使用")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var memberSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("成员列表")
                .font(.title3.weight(.semibold))

            ForEach(viewModel.members) { member in
                FamilyMemberCard(member: member)
            }
        }
    }

    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷设置")
                .font(.title3.weight(.semibold))

            HStack {
                Image(systemName: "bell.badge")
                Text("通知权限检查")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct FamilyMemberCard: View {
    let member: FamilyMember

    private var channelLabel: String {
        switch member.notificationChannel {
        case .app:
            return "APP"
        case .wechat:
            return "微信"
        case .whatsapp:
            return "WhatsApp"
        case .sms:
            return "短信"
        }
    }

    private var notificationText: String {
        member.notificationsEnabled ? "通知已开启" : "通知未开启"
    }

    private var roleBadgeIcon: String? {
        switch member.permission {
        case .owner, .manager:
            return "crown"
        case .executor, .viewer:
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.purple.opacity(0.12))
                .frame(width: 50, height: 50)
                .overlay {
                    Text(member.avatarEmoji ?? "🙂")
                        .font(.title2)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(member.displayName)
                        .font(.title3.weight(.semibold))
                    if let roleBadgeIcon {
                        Image(systemName: roleBadgeIcon)
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 6) {
                    Text(channelLabel)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                    Label(notificationText, systemImage: "bell")
                        .font(.subheadline)
                        .foregroundStyle(member.notificationsEnabled ? .green : .orange)
                }
            }
            Spacer()
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1.5)
        )
    }
}

#Preview {
    FamilyView()
}
