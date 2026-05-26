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
                    Text("群组")
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
                familyViewModel: viewModel,
                isSubmitting: viewModel.isLoading,
                canDisband: viewModel.canDisbandCurrentHousehold,
                errorMessage: renameErrorMessage,
                onSubmit: { newName in
                    await renameCurrentHousehold(to: newName)
                },
                onDisband: { userInput in
                    await submitDisbandHousehold(userInput: userInput)
                }
            )
            .presentationDetents([.large])
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
        .alert("提示", isPresented: transferSuccessToastBinding) {
            Button("好的", role: .cancel) {
                viewModel.acknowledgeTransferSuccessToast()
            }
        } message: {
            Text(viewModel.transferSuccessToastMessage ?? "")
        }
        .alert(String(localized: "Are you sure you want to leave this group?"), isPresented: $viewModel.showLeaveConfirmation) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Leave Group"), role: .destructive) {
                Task { await submitLeaveHousehold() }
            }
        } message: {
            Text("After leaving, you won't be able to view tasks and messages in this group.")
        }
        .alert(String(localized: "Notice"), isPresented: $viewModel.showCreatorBlockAlert) {
            Button(String(localized: "Got it"), role: .cancel) {}
        } message: {
            Text("You are the creator of this group. Transfer ownership or disband the group before leaving.")
        }
        .alert(String(localized: "Could not leave group"), isPresented: leaveErrorAlertBinding) {
            Button(String(localized: "Got it"), role: .cancel) {
                viewModel.acknowledgeLeaveError()
            }
        } message: {
            Text(viewModel.leaveErrorMessage ?? String(localized: "Please try again later."))
        }
    }

    private var leaveErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.leaveErrorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    viewModel.acknowledgeLeaveError()
                }
            }
        )
    }

    private var transferSuccessToastBinding: Binding<Bool> {
        Binding(
            get: { viewModel.transferSuccessToastMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    viewModel.acknowledgeTransferSuccessToast()
                }
            }
        )
    }

    // MARK: - List Body

    @ViewBuilder
    private var familyListBody: some View {
        List {
            if viewModel.isLoading && viewModel.hasLoadedOnce == false {
                ProgressView("正在加载成员档案…")
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
                            subtitle: memberListSubtitle(for: creator),
                            isVirtualUser: creator.isVirtualUser,
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
                            subtitle: memberListSubtitle(for: profile),
                            isVirtualUser: profile.isVirtualUser,
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
            Text("还没有成员档案")
                .font(.headline)
            Text("添加第一位成员，一起分工协作、温柔提醒每一天。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button("添加群组成员") {
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
            Text("群组成员")
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
            .accessibilityLabel(isSortingMembers ? "完成排序" : "排序群组成员")

            Button {
                addMemberRoute = .entry
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加群组成员")
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
        if profile.currentRole == MembershipRole.creator.rawValue { return true }
        return resolvedMembership(for: profile)?.hasRole(.creator) == true
    }

    private func resolvedMembership(for profile: FamilyProfile) -> HouseholdMembership? {
        profile.primaryMembership ?? viewModel.membership(for: profile)
    }

    private func rawPhoneForList(for profile: FamilyProfile) -> String? {
        profile.profileMainPhoneForDisplay
    }

    /// 列表第二行：角色说明或档案联系邮箱。
    private func memberListSubtitle(for profile: FamilyProfile) -> String {
        let membership = resolvedMembership(for: profile)
        guard let membership else {
            return profile.isVirtualUser ? contactSubtitleLine(for: profile) : "群组成员"
        }
        switch membership.parsedRole {
        case .creator, .admin:
            return contactSubtitleLine(for: profile)
        case .member:
            return membership.parsedRole?.displayTitle ?? "成员"
        case .none:
            return profile.isVirtualUser ? contactSubtitleLine(for: profile) : "群组成员"
        }
    }

    private func contactSubtitleLine(for profile: FamilyProfile) -> String {
        let email = profile.profileEmailForDisplay ?? ""
        let title = profile.displayName
        if email.isEmpty == false, email == title {
            return ""
        }
        return email
    }

    /// 行内显著角色：创建者优先于管理员；普通成员不展示胶囊。
    private func prominentListRole(for profile: FamilyProfile) -> MembershipRole? {
        if profile.currentRole == MembershipRole.creator.rawValue { return .creator }
        if profile.currentRole == MembershipRole.admin.rawValue { return .admin }
        if let role = resolvedMembership(for: profile)?.parsedRole {
            switch role {
            case .creator, .admin:
                return role
            case .member:
                return nil
            }
        }
        return nil
    }

    private func maskedPhoneForList(for profile: FamilyProfile) -> String? {
        guard let raw = rawPhoneForList(for: profile) else { return nil }
        return FamilyMemberRowView.maskPhoneForDisplay(raw)
    }

    /// 详情页「角色」一行：仅档案成员展示「成员档案」标签式文案。
    private func detailIdentitySubtitle(for profile: FamilyProfile) -> String {
        if profile.isVirtualUser {
            return "成员档案"
        }
        if let membership = resolvedMembership(for: profile) {
            return membership.parsedRole?.displayTitle ?? "群组成员"
        }
        return "群组成员"
    }

    private var leaveHouseholdSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(role: .destructive) {
                viewModel.requestToLeave()
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isLeaving {
                        ProgressView()
                    } else {
                        Text("Leave Group")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(viewModel.isLeaving)
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
        return currentMembership.parsedRole ?? .member
    }

    @MainActor
    private func renameCurrentHousehold(to newName: String) async {
        renameErrorMessage = nil
        guard let householdId = appRouter.selectedHouseholdId else {
            renameErrorMessage = "当前未选择群组。"
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
    private func submitDisbandHousehold(userInput: String) async -> Bool {
        guard let householdId = appRouter.selectedHouseholdId else { return false }
        let currentName = appRouter.selectedHouseholdName ?? ""
        let success = await viewModel.confirmDisband(
            householdId: householdId,
            currentName: currentName,
            userInputName: userInput
        )
        guard success else { return false }

        isShowingRenameHouseholdSheet = false
        await orgRoutingViewModel.fetchMyHouseholds(appRouter: appRouter)
        try? await Task.sleep(nanoseconds: 280_000_000)
        withAnimation {
            appRouter.exitToOrgHubAfterDisband()
        }
        await appRouter.refreshStateFromBackend()
        await orgRoutingViewModel.fetchMyHouseholds(appRouter: appRouter)
        return true
    }

    @MainActor
    private func submitLeaveHousehold() async {
        guard let householdId = appRouter.selectedHouseholdId else { return }
        let success = await viewModel.confirmLeave(householdId: householdId, appRouter: appRouter)
        guard success else { return }
        isShowingRenameHouseholdSheet = false
        await orgRoutingViewModel.fetchMyHouseholds(appRouter: appRouter)
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
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var familyViewModel: FamilyViewModel
    @State private var name: String
    @State private var showDisbandConfirmation = false
    private let initialName: String
    let isSubmitting: Bool
    let canDisband: Bool
    let errorMessage: String?
    let onSubmit: @MainActor (String) async -> Void
    let onDisband: @MainActor (String) async -> Bool

    init(
        initialName: String,
        familyViewModel: FamilyViewModel,
        isSubmitting: Bool,
        canDisband: Bool,
        errorMessage: String?,
        onSubmit: @escaping @MainActor (String) async -> Void,
        onDisband: @escaping @MainActor (String) async -> Bool
    ) {
        self.familyViewModel = familyViewModel
        _name = State(initialValue: initialName)
        self.initialName = initialName
        self.isSubmitting = isSubmitting
        self.canDisband = canDisband
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
        self.onDisband = onDisband
    }

    private var isDisbanding: Bool {
        familyViewModel.isDisbanding
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        let normalizedInitial = initialName.trimmingCharacters(in: .whitespacesAndNewlines)
        return isSubmitting == false
            && isDisbanding == false
            && trimmedName.isEmpty == false
            && trimmedName != normalizedInitial
    }

    var body: some View {
        NavigationStack {
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

                    if familyViewModel.canTransferOwnership {
                        transferOwnershipRow
                    }

                    if canDisband {
                        disbandHouseholdSection
                    } else if familyViewModel.canLeaveCurrentHousehold {
                        leaveHouseholdSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("群组设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .disabled(isSubmitting || isDisbanding)
                }
            }
            .sheet(isPresented: $showDisbandConfirmation) {
                DisbandHouseholdConfirmationSheet(
                    familyViewModel: familyViewModel,
                    householdName: initialName,
                    onConfirm: { userInput in
                        await onDisband(userInput)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(familyViewModel.isDisbanding)
            }
        }
    }

    private var organizationNameField: some View {
        TextField("输入群组名称…", text: $name)
            .textInputAutocapitalization(.words)
            .disabled(isSubmitting || isDisbanding)
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
                    Text("保存更改")
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
        NavigationLink {
            TransferOwnershipView(familyViewModel: familyViewModel) {
                dismiss()
            }
        } label: {
            settingsNavigationRow(
                title: "转移所有权",
                systemImage: "person.2.badge.gearshape"
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting || isDisbanding)
    }

    private var disbandHouseholdSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("危险操作")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .textCase(.uppercase)

            Button(role: .destructive) {
                showDisbandConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .font(.body)
                    Text("Disband Group")
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || isDisbanding || familyViewModel.isLeaving)

            Text("解散后所有成员将被移除，任务与邀请码将被永久清空。此操作不可撤销。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var leaveHouseholdSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(role: .destructive) {
                familyViewModel.requestToLeave()
            } label: {
                HStack(spacing: 12) {
                    if familyViewModel.isLeaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.body)
                        Text("Leave Group")
                            .font(.body.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || isDisbanding || familyViewModel.isLeaving)
        }
        .padding(.top, 8)
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
}

private struct DisbandHouseholdConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var familyViewModel: FamilyViewModel
    let householdName: String
    let onConfirm: @MainActor (String) async -> Bool

    @State private var disbandInputName = ""

    private var normalizedExpectedName: String {
        householdName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedInputName: String {
        disbandInputName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canConfirmDisband: Bool {
        familyViewModel.isDisbanding == false
            && normalizedInputName.isEmpty == false
            && normalizedInputName == normalizedExpectedName
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(alignment: .leading, spacing: 18) {
                    Text("解散群组操作不可逆")
                        .font(.headline)

                    Text("此操作不可逆！所有成员将被移除，任务、评论反馈及邀请码将被永久清空。请输入当前群组名称「\(householdName)」以确认解散。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("请输入群组名称以确认", text: $disbandInputName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        let snapshot = disbandInputName
                        Task { @MainActor in
                            let succeeded = await onConfirm(snapshot)
                            if succeeded {
                                dismiss()
                            }
                        }
                    } label: {
                        Group {
                            if familyViewModel.isDisbanding {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("确认解散")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(canConfirmDisband == false)

                    Spacer()
                }
                .padding(20)
                .disabled(familyViewModel.isDisbanding)

                if familyViewModel.isDisbanding {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("正在解散群组，请稍候…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(radius: 10)
                }
            }
            .navigationTitle("确认解散群组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .disabled(familyViewModel.isDisbanding)
                }
            }
            .alert("解散失败", isPresented: $familyViewModel.showDisbandErrorAlert) {
                Button("我知道了", role: .cancel) {}
            } message: {
                Text(familyViewModel.disbandError ?? "未知错误，请重试")
            }
        }
    }
}

#Preview {
    FamilyView()
        .environmentObject(AppRouter())
}
