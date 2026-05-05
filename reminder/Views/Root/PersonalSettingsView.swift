import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

struct PersonalSettingsView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var showsUpgradeAlert = false
    @State private var displayName = "xiong gao"
    @State private var accountSubtitle = "王家小院 - 管理员"
    @State private var isSigningOut = false
    @State private var signOutErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    personalInfoRow

                    Button {
                        showsUpgradeAlert = true
                    } label: {
                        upgradeCard
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section("系统设置") {
                    SettingsRow(
                        title: "语言",
                        systemImage: "character.rtl",
                        iconForeground: .blue,
                        iconBackground: Color.blue.opacity(0.16)
                    )
                    SettingsRow(
                        title: "密码与面容 ID",
                        systemImage: "faceid",
                        iconForeground: .purple,
                        iconBackground: Color.purple.opacity(0.16)
                    )
                    SettingsRow(
                        title: "导入与集成",
                        systemImage: "square.and.arrow.down",
                        iconForeground: .green,
                        iconBackground: Color.green.opacity(0.16),
                        showsChevron: false
                    )
                }

                Section("支持与关于") {
                    SettingsRow(
                        title: "帮助与反馈",
                        systemImage: "questionmark.circle",
                        iconForeground: .orange,
                        iconBackground: Color.orange.opacity(0.16)
                    )
                    SettingsRow(
                        title: "关于 WeFamily",
                        systemImage: "info.circle",
                        iconForeground: .teal,
                        iconBackground: Color.teal.opacity(0.16)
                    )
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await signOut()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSigningOut {
                                ProgressView()
                            } else {
                                Text("退出登录")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSigningOut)
                }
            }
            .listStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("个人设置")
            .alert("敬请期待", isPresented: $showsUpgradeAlert) {
                Button("我知道了", role: .cancel) {}
            } message: {
                Text("该功能即将上线，感谢您的关注")
            }
            .alert("退出失败", isPresented: Binding(
                get: { signOutErrorMessage != nil },
                set: { shouldShow in
                    if shouldShow == false { signOutErrorMessage = nil }
                }
            )) {
                Button("我知道了", role: .cancel) {}
            } message: {
                Text(signOutErrorMessage ?? "请稍后重试。")
            }
            .task {
                await loadCurrentUserProfile()
            }
        }
    }

    private var personalInfoRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: 17, weight: .semibold))
                Text(accountSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var upgradeCard: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.86, blue: 0.44),
                        Color(red: 0.95, green: 0.67, blue: 0.23),
                        Color(red: 0.86, green: 0.52, blue: 0.15)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 56)
            .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 4)
            .overlay {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("解锁 WeFamily AI 语音统筹高级版")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.black.opacity(0.78))
                .padding(.horizontal, 12)
            }
    }

    private func signOut() async {
        guard isSigningOut == false else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        #if canImport(Supabase)
        do {
            let supabase = SupabaseManager.shared.client
            try await supabase.auth.signOut()
            await appRouter.refreshStateFromBackend()
        } catch {
            signOutErrorMessage = error.localizedDescription
        }
        #else
        signOutErrorMessage = "当前构建环境未包含 Supabase SDK。"
        #endif
    }

    private func loadCurrentUserProfile() async {
        #if canImport(Supabase)
        let supabase = SupabaseManager.shared.client
        // 预留：如 SDK 版本提供同步用户对象，可直接使用
        // let user = supabase.auth.currentUser
        do {
            let session = try await supabase.auth.session
            let user = session.user
            if let email = user.email, email.isEmpty == false {
                displayName = email
            } else {
                displayName = user.id.uuidString
            }
        } catch {
            // 保持默认占位文案，不阻断页面展示
        }
        #endif
    }
}

private struct SettingsRow: View {
    let title: String
    let systemImage: String
    let iconForeground: Color
    let iconBackground: Color
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconForeground)
                .frame(width: 28, height: 28)
                .background(iconBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(title)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    PersonalSettingsView()
        .environmentObject(AppRouter())
}
