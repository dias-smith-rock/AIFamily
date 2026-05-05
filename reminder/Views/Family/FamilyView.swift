import SwiftUI

struct FamilyView: View {
    private let topFamilyBarOffset: CGFloat = 56
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeFamilyViewModel()
    @StateObject private var authViewModel = AppViewModels.makeAuthViewModel()
    @State private var keyword = ""
    @State private var showsInviteSheet = false
    @State private var showsLoginSheet = false
    @State private var showsRenameHouseholdSheet = false
    @State private var renameErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    inviteButton
                    memberFilterField
                    memberContent
                    quickSection
                }
                .padding(.horizontal, 16)
                .padding(.top, topFamilyBarOffset)
                .padding(.bottom, 96)
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
            InviteMemberSheet { member in
                guard let created = await viewModel.createMember(member) else {
                    return nil
                }
                return await viewModel.generateSignedInviteLink(for: created)
            }
            .presentationDetents([.medium, .large])
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
                showsInviteSheet = true
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

            Text("支持 App / 微信 / 邮箱触达")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var memberSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("成员列表")
                .font(.title3.weight(.semibold))

            ForEach(filteredMembers) { member in
                FamilyMemberCard(member: member)
            }
        }
    }

    private var memberFilterField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索成员姓名", text: $keyword)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var memberContent: some View {
        if viewModel.isLoading && viewModel.hasLoadedOnce == false {
            ProgressView("正在加载成员...")
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
        } else if filteredMembers.isEmpty {
            memberEmptyState
        } else {
            memberSection
        }
    }

    private var filteredMembers: [HouseholdMembership] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return viewModel.members }
        return viewModel.members.filter { member in
            member.nickname.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var memberEmptyState: some View {
        let isFirstEmpty = viewModel.members.isEmpty
        return EmptyStateView(
            systemImage: isFirstEmpty ? "person.2.badge.plus" : "line.3.horizontal.decrease.circle",
            title: isFirstEmpty ? "还没有家庭成员" : "没有匹配成员",
            message: isFirstEmpty
                ? "添加家人后，你可以为 TA 分配任务并接收反馈。"
                : "当前搜索条件下没有结果，试试更短的关键词。",
            primaryActionTitle: isFirstEmpty ? "邀请新成员" : "清空搜索",
            primaryAction: {
                if isFirstEmpty {
                    showsInviteSheet = true
                } else {
                    keyword = ""
                }
            },
            secondaryActionTitle: isFirstEmpty ? "重新加载" : nil,
            secondaryAction: isFirstEmpty ? {
                Task {
                    await viewModel.loadMembers()
                }
            } : nil
        )
    }

    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷设置")
                .font(.title3.weight(.semibold))

            Button {
                renameErrorMessage = nil
                showsRenameHouseholdSheet = true
            } label: {
                HStack {
                    Image(systemName: "textformat")
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
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(appRouter.selectedHouseholdId == nil)

            NavigationLink {
                InviteConsumeDemoView()
            } label: {
                HStack {
                    Image(systemName: "link.badge.plus")
                    Text("邀请链接消费调试")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
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

// MARK: - Invite Sheet

private struct InviteMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter

    @State private var nickname = ""
    @State private var contactMethod: ContactMethod = .wechat
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var isSubmitting = false
    @State private var generatedLink: URL?
    @State private var submitError: String?

    let onCreateMember: (HouseholdMembership) async -> URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("创建影子档案")
                            .font(.system(size: 22, weight: .bold))
                        Text("长辈或保姆无需注册，创建后可直接分发邀请链接。")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    nicknameField
                    contactMethodPicker
                    phoneField
                    emailField
                    createButton

                    if let generatedLink {
                        inviteLinkCard(link: generatedLink)
                    }

                    if let submitError {
                        Text(submitError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var nicknameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("成员称呼")
                .font(.system(size: 14, weight: .semibold))
            TextField("例如：奶奶 / 王阿姨", text: $nickname)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var contactMethodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("触达渠道")
                .font(.system(size: 14, weight: .semibold))
            Picker("触达渠道", selection: $contactMethod) {
                ForEach(ContactMethod.allCases, id: \.self) { value in
                    Text(value.displayTitle).tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("手机号（可选）")
                .font(.system(size: 14, weight: .semibold))
            TextField("用于短信或后续绑定", text: $phoneNumber)
                .textFieldStyle(.plain)
                .keyboardType(.phonePad)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("邮箱（可选）")
                .font(.system(size: 14, weight: .semibold))
            TextField("用于邮件邀请或登录", text: $email)
                .textFieldStyle(.plain)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var createButton: some View {
        Button {
            Task {
                await createShadowMember()
            }
        } label: {
            if isSubmitting {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                Text("创建并生成邀请链接")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .disabled(isSubmitting || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .buttonStyle(.borderedProminent)
    }

    private func inviteLinkCard(link: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("邀请链接已生成", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)

            Text(link.absoluteString)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)

            ShareLink(item: link) {
                Label("分享邀请链接", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func createShadowMember() async {
        submitError = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmedName = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            submitError = "请先填写成员称呼。"
            return
        }

        let now = Date()
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let householdId = appRouter.selectedHouseholdId else {
            submitError = "当前未选择家庭，请先切换家庭后再邀请。"
            return
        }

        let member = HouseholdMembership(
            id: UUID(),
            householdId: householdId,
            userId: nil,
            role: .member,
            nickname: trimmedName,
            avatarUrl: nil,
            contactMethod: contactMethod,
            phoneNumber: trimmedPhone.isEmpty ? nil : trimmedPhone,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            status: .pending,
            joinedAt: nil,
            createdAt: now,
            updatedAt: now
        )

        guard let signedLink = await onCreateMember(member) else {
            submitError = "创建成功，但签名链接生成失败，请稍后重试。"
            return
        }
        generatedLink = signedLink
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

// MARK: - Display Helpers

private extension ContactMethod {
    var displayTitle: String {
        switch self {
        case .appPush: return "App"
        case .wechat: return "微信"
        case .email: return "邮箱"
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

    var badgeIcon: String? {
        switch self {
        case .creator, .admin: return "crown"
        case .member: return nil
        }
    }
}

private extension MembershipStatus {
    var displayTitle: String {
        switch self {
        case .active: return "已激活"
        case .pending: return "待审批"
        case .disabled: return "已停用"
        }
    }

    var displayColor: Color {
        switch self {
        case .active: return .green
        case .pending: return .orange
        case .disabled: return .secondary
        }
    }
}

// MARK: - Member Card

private struct FamilyMemberCard: View {
    let member: HouseholdMembership

    private var channelLabel: String {
        member.contactMethod.displayTitle
    }

    private var avatarText: String {
        String(member.nickname.prefix(1))
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.purple.opacity(0.12))
                .frame(width: 50, height: 50)
                .overlay {
                    Text(avatarText)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.purple)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(member.nickname)
                        .font(.title3.weight(.semibold))
                    if let badgeIcon = member.role.badgeIcon {
                        Image(systemName: badgeIcon)
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
                    Label(member.role.displayTitle, systemImage: "person.text.rectangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Label(member.status.displayTitle, systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .foregroundStyle(member.status.displayColor)
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

// MARK: - Login Sheet

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
