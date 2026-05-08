import SwiftUI

struct FamilyView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeFamilyViewModel()
    @StateObject private var authViewModel = AppViewModels.makeAuthViewModel()
    @State private var showsInviteSheet = false
    @State private var showsLoginSheet = false
    @State private var showsRenameHouseholdSheet = false
    @State private var renameErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlobalHeaderView {
                    Text("我的家庭")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                } trailing: {
                    Button {
                        showsInviteSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.ColorToken.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加家庭成员")
                }

                ScrollView {
                    LazyVStack(spacing: 12) {
                        familyListBody
                        addMemberDashedCard
                        if canManageHousehold {
                            householdProfileSection
                        }
                        if isMemberRole {
                            leaveHouseholdSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 96)
                }
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .task {
            viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
            await viewModel.loadMembers()
            showsLoginSheet = viewModel.requiresLogin
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
            viewModel.setHouseholdContext(newValue)
            Task {
                await viewModel.loadMembers()
                showsLoginSheet = viewModel.requiresLogin
            }
        }
        .onChange(of: viewModel.requiresLogin) { _, requiresLogin in
            showsLoginSheet = requiresLogin
        }
        .sheet(isPresented: $showsInviteSheet) {
            InviteMemberView(
                currentHouseholdId: appRouter.selectedHouseholdId,
                creatorMembershipId: appRouter.selectedMembershipId
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsLoginSheet) {
            FamilySessionLoginSheet(viewModel: authViewModel) {
                await viewModel.didLoginSuccessfully()
                showsLoginSheet = viewModel.requiresLogin
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsRenameHouseholdSheet) {
            RenameHouseholdSheet(
                initialName: appRouter.selectedHouseholdName ?? "",
                isSubmitting: viewModel.isLoading,
                errorMessage: renameErrorMessage,
                onSubmit: { newName in
                    await renameCurrentHousehold(to: newName)
                }
            )
            .presentationDetents([.fraction(0.35), .medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - List Body

    @ViewBuilder
    private var familyListBody: some View {
        if viewModel.isLoading && viewModel.hasLoadedOnce == false {
            ProgressView("正在加载家人档案…")
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("加载失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重新加载") {
                    Task {
                        await viewModel.loadMembers()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if viewModel.profiles.isEmpty {
            profilesEmptyState
        } else {
            ForEach(viewModel.profiles) { profile in
                FamilyMemberRowView(profile: profile, subtitle: profileSubtitle(for: profile))
            }
        }
    }

    private var profilesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.ColorToken.accent.opacity(0.85))
                .symbolRenderingMode(.hierarchical)
            Text("还没有家人档案")
                .font(.headline)
            Text("添加第一位家人，一起分工协作、温柔提醒每一天。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button("添加家庭成员") {
                showsInviteSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var addMemberDashedCard: some View {
        Button {
            showsInviteSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                    .font(.body.weight(.semibold))
                Text("添加家庭成员")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加家庭成员")
    }

    private func profileSubtitle(for profile: FamilyProfile) -> String {
        if profile.userId == nil {
            return "托管角色"
        }
        if let uid = profile.userId,
           let membership = viewModel.members.first(where: { $0.userId == uid }) {
            return membership.role.displayTitle
        }
        return "家庭成员"
    }

    private var leaveHouseholdSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("成员操作")
                .font(AppTheme.FontToken.section)

            Button(role: .destructive) {
                // TODO: 调用 supabase 删除当前用户的 membership 记录，并跳转回路由选择页。
            } label: {
                HStack {
                    Spacer()
                    Text("退出该家庭")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private var householdProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("家庭资料")
                .font(AppTheme.FontToken.section)

            Button {
                renameErrorMessage = nil
                showsRenameHouseholdSheet = true
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("修改家庭名称")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(appRouter.selectedHouseholdName ?? "未命名家庭")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(appRouter.selectedHouseholdId == nil)
        }
    }

    private var canManageHousehold: Bool {
        switch currentUserRole {
        case .creator, .admin:
            return true
        case .member:
            return false
        }
    }

    private var isMemberRole: Bool {
        currentUserRole == .member
    }

    private var currentUserRole: MembershipRole {
        guard
            let selectedMembershipId = appRouter.selectedMembershipId,
            let currentMembership = viewModel.members.first(where: { $0.id == selectedMembershipId })
        else {
            return .member
        }
        return currentMembership.role
    }

    @MainActor
    private func renameCurrentHousehold(to newName: String) async {
        renameErrorMessage = nil
        guard let householdId = appRouter.selectedHouseholdId else {
            renameErrorMessage = "当前未选择家庭。"
            return
        }

        let renameFailureMessage = await viewModel.renameHousehold(
            householdId: householdId,
            newName: newName
        )
        if let renameFailureMessage {
            renameErrorMessage = renameFailureMessage
            return
        }

        await appRouter.refreshStateFromBackend()
        showsRenameHouseholdSheet = false
    }
}

private struct RenameHouseholdSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    let isSubmitting: Bool
    let errorMessage: String?
    let onSubmit: @MainActor (String) async -> Void

    init(
        initialName: String,
        isSubmitting: Bool,
        errorMessage: String?,
        onSubmit: @escaping @MainActor (String) async -> Void
    ) {
        _name = State(initialValue: initialName)
        self.isSubmitting = isSubmitting
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("家庭名称")
                    .font(.system(size: 14, weight: .semibold))
                TextField("请输入新的家庭名称", text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                }

                Button {
                    let snapshot = String(name)
                    Task { @MainActor in
                        await onSubmit(snapshot)
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    } else {
                        Text("保存名称")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .disabled(isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(16)
            .navigationTitle("重命名家庭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension MembershipRole {
    var displayTitle: String {
        switch self {
        case .creator: return "创建者"
        case .admin: return "管理员"
        case .member: return "成员"
        }
    }
}

private struct FamilySessionLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AuthViewModel
    let onLoginSuccess: () async -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("需要先登录")
                    .font(.system(size: 26, weight: .bold))
                Text("检测到当前会话无效，请先登录再加载家庭成员。")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("登录方式", selection: $viewModel.selectedMethod) {
                    ForEach(AuthViewModel.LoginMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.selectedMethod == .magicLink {
                    TextField("邮箱地址", text: $viewModel.email)
                        .textFieldStyle(.roundedBorder)
                }

                if viewModel.selectedMethod == .phoneOTP {
                    TextField("手机号", text: $viewModel.phone)
                        .keyboardType(.phonePad)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    Task {
                        await viewModel.submit()
                        if viewModel.isLoggedIn {
                            await onLoginSuccess()
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("登录并继续")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("刷新会话状态") {
                    Task {
                        await viewModel.refreshSessionState()
                        if viewModel.isLoggedIn {
                            await onLoginSuccess()
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.bordered)

                Text(viewModel.statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("会话校验")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    FamilyView()
        .environmentObject(AppRouter())
}
