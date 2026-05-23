import SwiftUI

private enum AddMemberRoute: Identifiable, Equatable {
    case entry
    case invite

    var id: String {
        switch self {
        case .entry: return "entry"
        case .invite: return "invite"
        }
    }
}

struct FamilyView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeFamilyViewModel()
    @StateObject private var authViewModel = AppViewModels.makeAuthViewModel()
    @State private var addMemberRoute: AddMemberRoute?
    @State private var isPresentingCreateLocalProfile = false
    @State private var isShowingLoginSheet = false
    @State private var isShowingRenameHouseholdSheet = false
    @State private var isShowingCreateOrganizationSheet = false
    @State private var newOrganizationName = ""
    @State private var createOrganizationError: String?
    @StateObject private var orgRoutingViewModel = AppViewModels.makeOrgRoutingViewModel()
    @State private var editingProfile: FamilyProfile?
    @State private var selectedProfileForDetail: FamilyProfile?
    @State private var isSortingMembers = false
    @State private var renameErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlobalHeaderView {
                    Text("家庭")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                }

                familyListBody
                    .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .task {
            viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
            viewModel.setMembershipContext(appRouter.selectedMembershipId)
            await viewModel.loadMembers()
            isShowingLoginSheet = viewModel.requiresLogin
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
            viewModel.setHouseholdContext(newValue)
            Task {
                await viewModel.loadMembers()
                isShowingLoginSheet = viewModel.requiresLogin
            }
        }
        .onChange(of: appRouter.selectedMembershipId) { _, newValue in
            viewModel.setMembershipContext(newValue)
            Task { await viewModel.loadMembers() }
        }
        .onChange(of: viewModel.requiresLogin) { _, requiresLogin in
            isShowingLoginSheet = requiresLogin
        }
        .sheet(item: $addMemberRoute) { route in
            switch route {
            case .entry:
                AddFamilyMemberEntrySheet(
                    canCreateProfileWithoutAccount: canManageHousehold,
                    onChooseInvite: { addMemberRoute = .invite },
                    onChooseCreateProfile: {
                        guard canManageHousehold else { return }
                        Task { @MainActor in
                            addMemberRoute = nil
                            await Task.yield()
                            isPresentingCreateLocalProfile = true
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .invite:
                InviteMemberView(
                    currentHouseholdId: appRouter.selectedHouseholdId,
                    creatorMembershipId: appRouter.selectedMembershipId
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $isPresentingCreateLocalProfile) {
            ProfileEditView(
                mode: .createLocalProfile,
                householdId: appRouter.selectedHouseholdId,
                canEdit: canManageHousehold,
                uploadAvatar: { data, profileId in
                    #if DEBUG
                    print("🔎 [FamilyDebug] FamilyView upload closure received data bytes=\(data.count)")
                    #endif
                    return await viewModel.uploadAvatar(data: data, profileId: profileId)
                },
                onSave: { householdId, draft in
                    await viewModel.createLocalProfile(householdId: householdId, draft: draft)
                }
            )
        }
        .sheet(isPresented: $isShowingLoginSheet) {
            FamilySessionLoginSheet(viewModel: authViewModel) {
                await viewModel.didLoginSuccessfully()
                isShowingLoginSheet = viewModel.requiresLogin
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $editingProfile) { profile in
            ProfileEditView(
                mode: .edit(profile),
                householdId: appRouter.selectedHouseholdId,
                canEdit: viewModel.canEditProfile(profile),
                uploadAvatar: { data, profileId in
                    #if DEBUG
                    print("🔎 [FamilyDebug] FamilyView upload closure received data bytes=\(data.count)")
                    #endif
                    return await viewModel.uploadAvatar(data: data, profileId: profileId)
                },
                onSave: { _, draft in
                    await viewModel.updateProfile(profile, draft: draft)
                }
            )
        }
        .fullScreenCover(item: $selectedProfileForDetail) { profile in
            ProfileDetailView(
                profile: profile,
                subtitle: detailIdentitySubtitle(for: profile),
                canEdit: viewModel.canEditProfile(profile),
                onEdit: {
                    selectedProfileForDetail = nil
                    editingProfile = profile
                }
            )
        }
        .sheet(isPresented: $isShowingRenameHouseholdSheet) {
            OrganizationSettingsSheet(
                initialName: appRouter.selectedHouseholdName ?? "",
                isSubmitting: viewModel.isLoading,
                errorMessage: renameErrorMessage,
                onSubmit: { newName in
                    await renameCurrentHousehold(to: newName)
                }
            )
            .presentationDetents([.height(OrganizationSettingsSheet.preferredDetentHeight)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingCreateOrganizationSheet) {
            CreateOrganizationSheet(
                organizationName: $newOrganizationName,
                inputError: $createOrganizationError,
                isSubmitting: orgRoutingViewModel.isCreating,
                onSubmit: {
                    await submitCreateOrganization()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - List Body

    @ViewBuilder
    private var familyListBody: some View {
        List {
            if viewModel.isLoading && viewModel.hasLoadedOnce == false {
                ProgressView("正在加载家人档案…")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .listRowBackground(Color.clear)
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
                .listRowBackground(Color.clear)
            } else if viewModel.orderedProfiles.isEmpty {
                Section {
                    householdSummaryRow
                    profilesEmptyState
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } else {
                Section {
                    householdSummaryRow
                        .listRowInsets(
                            EdgeInsets(
                                top: 2,
                                leading: 16,
                                bottom: creatorProfile != nil ? 2 : 8,
                                trailing: 16
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(creatorProfile == nil ? .automatic : .hidden, edges: .bottom)

                    if let creator = creatorProfile {
                        FamilyMemberRowView(
                            profile: creator,
                            displayTitle: displayTitleForRow(creator),
                            subtitle: memberListSubtitle(for: creator),
                            isLocalProfile: creator.isLocalProfile,
                            prominentRole: prominentListRole(for: creator),
                            maskedPhoneLine: maskedPhoneForList(for: creator),
                            rawPhoneNumber: rawPhoneForList(for: creator)
                        ) {
                            presentMemberFlow(for: creator)
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden, edges: .top)
                    }
                }

                Section {
                    ForEach(membersExcludingCreator) { profile in
                        FamilyMemberRowView(
                            profile: profile,
                            displayTitle: displayTitleForRow(profile),
                            subtitle: memberListSubtitle(for: profile),
                            isLocalProfile: profile.isLocalProfile,
                            prominentRole: prominentListRole(for: profile),
                            maskedPhoneLine: maskedPhoneForList(for: profile),
                            rawPhoneNumber: rawPhoneForList(for: profile)
                        ) {
                            presentMemberFlow(for: profile)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                    .onMove { indexSet, destination in
                        guard isSortingMembers else { return }
                        viewModel.moveNonCreatorProfiles(fromOffsets: indexSet, toOffset: destination)
                    }
                } header: {
                    otherMembersSectionHeader
                }

                if isMemberRole {
                    Section("成员操作") {
                        leaveHouseholdSection
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(isSortingMembers ? .active : .inactive))
        .contentMargins(.top, 0, for: .scrollContent)
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
                addMemberRoute = .entry
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    /// 组织名称 + 图标：标题区切换组织，副标题进入组织设置。
    private var householdSummaryRow: some View {
        householdSummaryRowContent
            .accessibilityElement(children: .contain)
    }

    private var householdSummaryRowContent: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                openOrganizationSettings()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.orange)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(currentOrganizationDisplayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            if canManageHousehold {
                                Image(systemName: "square.and.pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("Organization Profile")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(canManageHousehold == false || appRouter.selectedHouseholdId == nil)

            OrganizationSwitcherChevronButton(
                isShowingCreateOrganization: $isShowingCreateOrganizationSheet
            )
        }
        .padding(.vertical, 6)
    }

    private var currentOrganizationDisplayName: String {
        let trimmed = appRouter.selectedHouseholdName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled Organization" : trimmed
    }

    private func openOrganizationSettings() {
        renameErrorMessage = nil
        isShowingRenameHouseholdSheet = true
    }

    private var otherMembersSectionHeader: some View {
        HStack(spacing: 16) {
            Text("家庭成员")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button {
                withAnimation(.snappy) {
                    isSortingMembers.toggle()
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.body)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSortingMembers ? "完成排序" : "排序家庭成员")

            Button {
                addMemberRoute = .entry
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加家庭成员")
        }
        .textCase(nil)
    }

    private var creatorProfile: FamilyProfile? {
        viewModel.orderedProfiles.first(where: { isCreatorProfile($0) })
    }

    private var membersExcludingCreator: [FamilyProfile] {
        viewModel.orderedProfiles.filter { isCreatorProfile($0) == false }
    }

    /// 有编辑权限时直接进入编辑页，否则进入只读详情。
    private func presentMemberFlow(for profile: FamilyProfile) {
        if viewModel.canEditProfile(profile) {
            editingProfile = profile
        } else {
            selectedProfileForDetail = profile
        }
    }

    private func isCreatorProfile(_ profile: FamilyProfile) -> Bool {
        resolvedMembership(for: profile)?.role == .creator
    }

    private func resolvedMembership(for profile: FamilyProfile) -> HouseholdMembership? {
        profile.primaryMembership ?? viewModel.membership(for: profile)
    }

    /// 列表主行「覆盖标题」：仅当 **没有有效称呼** 时用邮箱作为主展示；有称呼时返回 `nil`，由 `FamilyMemberRowView` 使用 `profile.name`。
    private func displayTitleForRow(_ profile: FamilyProfile) -> String? {
        let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty == false, trimmedName != "未命名成员" {
            return nil
        }
        if let fromProfile = profile.profileEmailForDisplay {
            return fromProfile
        }
        guard profile.userId != nil else { return nil }
        let email = resolvedMembership(for: profile)?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? nil : email
    }

    private func rawPhoneForList(for profile: FamilyProfile) -> String? {
        if let fromProfile = profile.profileMainPhoneForDisplay {
            return fromProfile
        }
        let raw = resolvedMembership(for: profile)?.phoneNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    /// 列表第二行：创建者/管理员已在行内胶囊展示，此处留空；普通成员显示「成员」。
    private func memberListSubtitle(for profile: FamilyProfile) -> String {
        let membership = resolvedMembership(for: profile)
        guard let membership else {
            return profile.isLocalProfile ? "" : "家庭成员"
        }
        switch membership.role {
        case .creator, .admin:
            return ""
        case .member:
            return membership.role.displayTitle
        }
    }

    /// 行内显著角色：创建者优先于管理员；普通成员不展示胶囊。
    private func prominentListRole(for profile: FamilyProfile) -> MembershipRole? {
        guard let role = resolvedMembership(for: profile)?.role else { return nil }
        switch role {
        case .creator, .admin:
            return role
        case .member:
            return nil
        }
    }

    private func maskedPhoneForList(for profile: FamilyProfile) -> String? {
        guard let raw = rawPhoneForList(for: profile) else { return nil }
        return FamilyMemberRowView.maskPhoneForDisplay(raw)
    }

    /// 详情页「角色」一行：仅档案成员展示「成员档案」标签式文案。
    private func detailIdentitySubtitle(for profile: FamilyProfile) -> String {
        if profile.isLocalProfile {
            return "成员档案"
        }
        if let membership = resolvedMembership(for: profile) {
            return membership.role.displayTitle
        }
        return "家庭成员"
    }

    private var leaveHouseholdSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        isShowingRenameHouseholdSheet = false
    }

    @MainActor
    private func submitCreateOrganization() async {
        createOrganizationError = nil
        let normalizedName = newOrganizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            createOrganizationError = "Organization name cannot be empty."
            return
        }

        guard let createdHouseholdId = await orgRoutingViewModel.createHousehold(displayName: normalizedName) else {
            createOrganizationError = orgRoutingViewModel.errorMessage
            return
        }

        newOrganizationName = ""
        isShowingCreateOrganizationSheet = false
        appRouter.preferHouseholdOnNextRefresh(createdHouseholdId)
        await appRouter.refreshStateFromBackend()
        viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
        await viewModel.loadMembers()
    }

}

private struct OrganizationSettingsSheet: View {
    static let preferredDetentHeight: CGFloat = 430

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    private let initialName: String
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
        self.initialName = initialName
        self.isSubmitting = isSubmitting
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        let normalizedInitial = initialName.trimmingCharacters(in: .whitespacesAndNewlines)
        return isSubmitting == false
            && trimmedName.isEmpty == false
            && trimmedName != normalizedInitial
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    organizationNameField

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    saveChangesButton
                    transferOwnershipRow
                    disbandOrganizationRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var headerBar: some View {
        ZStack {
            Text("Organization Settings")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .disabled(isSubmitting)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private var organizationNameField: some View {
        TextField("Enter organization name...", text: $name)
            .textInputAutocapitalization(.words)
            .disabled(isSubmitting)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var saveChangesButton: some View {
        Button {
            let snapshot = trimmedName
            Task { @MainActor in
                await onSubmit(snapshot)
            }
        } label: {
            Group {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Save Changes")
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                canSave ? Color.accentColor : Color.accentColor.opacity(0.45),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(canSave == false)
    }

    private var transferOwnershipRow: some View {
        Button {
            // 预留：转移所有权流程
        } label: {
            settingsNavigationRow(
                title: "Transfer Ownership",
                systemImage: "person"
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    private var disbandOrganizationRow: some View {
        Button(role: .destructive) {
            // 预留：解散组织流程
        } label: {
            settingsDestructiveRow(
                title: "Disband Organization",
                systemImage: "trash"
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    private func settingsNavigationRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, alignment: .center)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingsDestructiveRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.red)
                .frame(width: 24, alignment: .center)

            Text(title)
                .font(.body)
                .foregroundStyle(.red)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    FamilyView()
        .environmentObject(AppRouter())
}
