import SwiftUI

struct FamilyView: View {
    @StateObject private var viewModel = AppViewModels.makeFamilyViewModel()
    @StateObject private var authViewModel = AppViewModels.makeAuthViewModel()
    @State private var keyword = ""
    @State private var showsInviteSheet = false
    @State private var showsLoginSheet = false

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
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadMembers()
            showsLoginSheet = viewModel.requiresLogin
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

            Text("支持微信/WhatsApp免安装使用")
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
                    _Concurrency.Task {
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

    private var filteredMembers: [FamilyMember] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return viewModel.members }
        return viewModel.members.filter { member in
            member.displayName.localizedCaseInsensitiveContains(trimmed)
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
                _Concurrency.Task {
                    await viewModel.loadMembers()
                }
            } : nil
        )
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
}

private struct InviteMemberSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var role: FamilyMember.FamilyRole = .grandparent
    @State private var channel: FamilyMember.NotificationChannel = .wechat
    @State private var phoneNumber = ""
    @State private var isSubmitting = false
    @State private var generatedLink: URL?
    @State private var submitError: String?

    let onCreateMember: (FamilyMember) async -> URL?

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

                    nameField
                    rolePicker
                    channelPicker
                    phoneField
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

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("成员称呼")
                .font(.system(size: 14, weight: .semibold))
            TextField("例如：奶奶 / 王阿姨", text: $displayName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("角色")
                .font(.system(size: 14, weight: .semibold))
            Picker("角色", selection: $role) {
                ForEach(FamilyMember.FamilyRole.allCases, id: \.self) { value in
                    Text(value.displayTitle).tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var channelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("触达渠道")
                .font(.system(size: 14, weight: .semibold))
            Picker("触达渠道", selection: $channel) {
                ForEach(FamilyMember.NotificationChannel.allCases, id: \.self) { value in
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

    private var createButton: some View {
        Button {
            _Concurrency.Task {
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
        .disabled(isSubmitting || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            submitError = "请先填写成员称呼。"
            return
        }

        let now = Date()
        let member = FamilyMember(
            id: UUID(),
            displayName: trimmedName,
            role: role,
            permission: .executor,
            notificationChannel: channel,
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phoneNumber,
            avatarEmoji: role.defaultAvatarEmoji,
            notificationsEnabled: true,
            inviteToken: "invite-\(UUID().uuidString.lowercased())",
            bindingStatus: .pending,
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

private extension FamilyMember.FamilyRole {
    static var allCases: [FamilyMember.FamilyRole] {
        [.father, .mother, .grandparent, .caregiver, .child]
    }

    var displayTitle: String {
        switch self {
        case .father:
            return "父亲"
        case .mother:
            return "母亲"
        case .grandparent:
            return "长辈"
        case .caregiver:
            return "保姆"
        case .child:
            return "孩子"
        }
    }

    var defaultAvatarEmoji: String {
        switch self {
        case .father:
            return "👨"
        case .mother:
            return "👩"
        case .grandparent:
            return "👵"
        case .caregiver:
            return "🧑"
        case .child:
            return "🧒"
        }
    }
}

private extension FamilyMember.NotificationChannel {
    static var allCases: [FamilyMember.NotificationChannel] {
        [.wechat, .app, .whatsapp, .sms]
    }

    var displayTitle: String {
        switch self {
        case .app:
            return "App"
        case .wechat:
            return "微信"
        case .whatsapp:
            return "WhatsApp"
        case .sms:
            return "短信"
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

    private var bindingText: String {
        switch member.bindingStatus {
        case .pending:
            return "待绑定"
        case .linked:
            return "已绑定"
        case .disabled:
            return "已停用"
        }
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
                Label(bindingText, systemImage: "link")
                    .font(.subheadline)
                    .foregroundStyle(member.bindingStatus == .linked ? .green : .secondary)
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
                    _Concurrency.Task {
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
                    _Concurrency.Task {
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
