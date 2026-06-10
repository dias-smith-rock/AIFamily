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
    @Environment(\.locale) private var locale
    @Environment(\.isGuestMode) private var isGuestMode
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator
    @ObservedObject private var authSessionGuard = AuthSessionGuard.shared
    @StateObject private var viewModel = AppViewModels.makeFamilyViewModel()
    @State private var addMemberRoute: AddMemberRoute?
    @State private var isPresentingCreateLocalProfile = false
    @State private var isShowingRenameHouseholdSheet = false
    @StateObject private var orgRoutingViewModel = AppViewModels.makeOrgRoutingViewModel()
    @State private var editingProfile: FamilyProfile?
    @State private var selectedProfileForDetail: FamilyProfile?
    @State private var isSortingMembers = false
    @State private var renameErrorMessage: String?
    @State private var showsGuestSignInAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlobalHeaderView(
                    leading: {
                        Text("群组")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                    },
                    trailing: {
                        if viewModel.canLeaveCurrentHousehold && isMemberRole {
                            Button {
                                viewModel.requestToLeave()
                            } label: {
                                if viewModel.isLeaving {
                                    ProgressView()
                                        .tint(.blue)
                                        .scaleEffect(0.85)
                                        .frame(width: 24, height: 24)
                                } else {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.body.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLeaving)
                            .accessibilityLabel(AppLocalized.string("退出群组", locale: locale))
                        } else {
                            EmptyView()
                        }
                    }
                )

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
            await handleRequiresLoginIfNeeded()
            Task { await appRouter.refreshSelectedHouseholdSnapshot() }
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
            viewModel.setHouseholdContext(newValue)
            Task {
                await viewModel.loadMembers()
                await handleRequiresLoginIfNeeded()
                Task { await appRouter.refreshSelectedHouseholdSnapshot() }
            }
        }
        .onChange(of: appRouter.selectedMembershipId) { _, newValue in
            viewModel.setMembershipContext(newValue)
            Task { await viewModel.loadMembers() }
        }
        .onChange(of: viewModel.requiresLogin) { _, needsLogin in
            guard needsLogin else { return }
            Task { await handleRequiresLoginIfNeeded() }
        }
        .task(id: appRouter.pendingOpenGroupSettings) {
            guard appRouter.pendingOpenGroupSettings else { return }
            appRouter.consumePendingOpenGroupSettingsRequest()
            openOrganizationSettings()
        }
        .sheet(item: $addMemberRoute) { route in
            switch route {
            case .entry:
                AddFamilyMemberEntrySheet(
                    canCreateProfileWithoutAccount: canCreateVirtualProfile,
                    onChooseInvite: {
                        guard viewModel.canAddMember(hasPremiumAccess: appRouter.hasPremiumAccess) else {
                            addMemberRoute = nil
                            appRouter.presentPremiumUpgrade()
                            return
                        }
                        addMemberRoute = .invite
                    },
                    onChooseCreateProfile: {
                        guard canCreateVirtualProfile else { return }
                        guard viewModel.canAddMember(hasPremiumAccess: appRouter.hasPremiumAccess) else {
                            addMemberRoute = nil
                            appRouter.presentPremiumUpgrade()
                            return
                        }
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
                    creatorMembershipId: appRouter.selectedMembershipId,
                    activeMemberCount: viewModel.activeMemberCount,
                    hasPremiumAccess: appRouter.hasPremiumAccess
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $isPresentingCreateLocalProfile) {
            ProfileEditView(
                mode: .createLocalProfile,
                householdId: appRouter.selectedHouseholdId,
                canEdit: canCreateVirtualProfile,
                uploadAvatar: { data, profileId in
                    #if DEBUG
                    print("🔎 [FamilyDebug] FamilyView upload closure received data bytes=\(data.count)")
                    #endif
                    return await viewModel.uploadAvatar(data: data, profileId: profileId)
                },
                onSave: { householdId, draft in
                    let result = await viewModel.createLocalProfile(
                        householdId: householdId,
                        draft: draft,
                        hasPremiumAccess: appRouter.hasPremiumAccess
                    )
                    if result == nil {
                        ReviewRedirectManager.shared.checkAndTriggerAlert(for: .virtualMember)
                    }
                    return result
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        }
        .fullScreenCover(item: $editingProfile) { profile in
            ProfileEditView(
                mode: .edit(profile),
                householdId: appRouter.selectedHouseholdId,
                canEdit: viewModel.canEditProfile(profile),
                memberRemoval: memberRemovalAction(for: profile),
                adminRoleToggle: adminRoleToggleAction(for: profile),
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
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        }
        .fullScreenCover(item: $selectedProfileForDetail) { profile in
            ProfileDetailView(
                profile: profile,
                roleLabel: detailRoleLabel(for: profile),
                canEdit: viewModel.canEditProfile(profile),
                onEdit: {
                    selectedProfileForDetail = nil
                    editingProfile = profile
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        }
        .sheet(isPresented: $isShowingRenameHouseholdSheet) {
            OrganizationSettingsSheet(
                initialName: appRouter.selectedHouseholdName ?? "",
                initialDescription: appRouter.selectedHouseholdDescription,
                familyViewModel: viewModel,
                isSubmitting: viewModel.isLoading,
                canDisband: viewModel.canDisbandCurrentHousehold,
                errorMessage: renameErrorMessage,
                onSubmit: { newName, description in
                    await renameCurrentHousehold(to: newName, description: description)
                },
                onDisband: { userInput in
                    await submitDisbandHousehold(userInput: userInput)
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("提示", isPresented: transferSuccessToastBinding) {
            Button("好的", role: .cancel) {
                viewModel.acknowledgeTransferSuccessToast()
            }
        } message: {
            Text(viewModel.transferSuccessToastMessage ?? "")
        }
        .alert("确定要退出该群组吗？", isPresented: $viewModel.showLeaveConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出群组", role: .destructive) {
                Task { await submitLeaveHousehold() }
            }
        } message: {
            Text("退出后您将无法查看群内的任务和消息。")
        }
        .alert("提示", isPresented: $viewModel.showCreatorBlockAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("您是此群组的创建者。退出前请先转移所有权或解散群组。")
        }
        .alert("退出群组失败", isPresented: leaveErrorAlertBinding) {
            Button("知道了", role: .cancel) {
                viewModel.acknowledgeLeaveError()
            }
        } message: {
            Text(viewModel.leaveErrorMessage ?? "请稍后重试。")
        }
        .guestSignInRequiredAlert(isPresented: $showsGuestSignInAlert)
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
                ProgressView(AppLocalized.string("正在加载成员档案…", locale: locale))
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .listRowBackground(Color.clear)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label(AppLocalized.string("加载中", locale: locale), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(AppLocalized.string("重新加载", locale: locale)) {
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
                            isVirtualUser: creator.isVirtualUser,
                            isCurrentUser: isCurrentUserProfile(creator),
                            prominentRole: prominentListRole(for: creator)
                        ) {
                            presentMemberFlow(for: creator)
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden, edges: .top)
                    }
                }

                Section {
                    if membersExcludingCreator.isEmpty {
                        otherMembersEmptyState
                    } else {
                        ForEach(membersExcludingCreator) { profile in
                            FamilyMemberRowView(
                                profile: profile,
                                isVirtualUser: profile.isVirtualUser,
                                isCurrentUser: isCurrentUserProfile(profile),
                                prominentRole: prominentListRole(for: profile)
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
                    }
                } header: {
                    otherMembersSectionHeader
                }

            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(isSortingMembers ? .active : .inactive))
        .contentMargins(.top, 0, for: .scrollContent)
        .refreshable {
            await viewModel.loadMembers()
        }
    }

    private var otherMembersEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)

            Text("暂无其他成员")
                .foregroundStyle(.secondary)

            Button("添加群组成员") {
                presentAddMemberFlow()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private func presentAddMemberFlow() {
        if isGuestMode {
            showsGuestSignInAlert = true
            return
        }
        guard viewModel.canAddMember(hasPremiumAccess: appRouter.hasPremiumAccess) else {
            appRouter.presentPremiumUpgrade()
            return
        }
        addMemberRoute = .entry
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
                presentAddMemberFlow()
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

                        organizationDescriptionSubtitle
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(canManageHousehold == false || appRouter.selectedHouseholdId == nil)

            Button {
                groupSwitcher.showSwitchGroupDialog = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换群组")
        }
        .padding(.vertical, 6)
    }

    private var currentOrganizationDisplayName: String {
        let trimmed = appRouter.selectedHouseholdName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return String(localized: "未命名群组") }
        return GuestSessionStore.displayHouseholdName(trimmed)
    }

    @ViewBuilder
    private var organizationDescriptionSubtitle: some View {
        let trimmed = appRouter.selectedHouseholdDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            Text(trimmed)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private func openOrganizationSettings() {
        renameErrorMessage = nil
        Task {
            await appRouter.refreshSelectedHouseholdSnapshot()
            isShowingRenameHouseholdSheet = true
        }
    }

    private func memberRemovalAction(for profile: FamilyProfile) -> ProfileEditView.MemberRemovalAction? {
        guard viewModel.shouldShowDeleteButton(for: profile) else { return nil }
        return ProfileEditView.MemberRemovalAction(
            buttonTitle: viewModel.deleteButtonTitle(for: profile),
            isVirtualMember: viewModel.isVirtualMember(profile),
            onDelete: { await viewModel.deleteOrRemoveMember(profile: profile) }
        )
    }

    private func adminRoleToggleAction(for profile: FamilyProfile) -> ProfileEditView.AdminRoleToggleAction? {
        viewModel.adminRoleToggleAction(for: profile)
    }

    private var otherMembersSectionHeader: some View {
        HStack(spacing: 16) {
            Text("群组成员")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if membersExcludingCreator.count >= 2 {
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
                .accessibilityLabel(
                    isSortingMembers
                        ? AppLocalized.string("完成排序", locale: locale)
                        : AppLocalized.string("排序群组成员", locale: locale)
                )
            }

            if membersExcludingCreator.isEmpty == false {
                Button {
                    presentAddMemberFlow()
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalized.string("添加群组成员", locale: locale))
            }
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

    private func isCurrentUserProfile(_ profile: FamilyProfile) -> Bool {
        guard let selectedMembershipId = appRouter.selectedMembershipId,
              let currentMembership = viewModel.members.first(where: { $0.id == selectedMembershipId }) else {
            return false
        }
        if currentMembership.profileId == profile.id {
            return true
        }
        return resolvedMembership(for: profile)?.id == selectedMembershipId
    }

    private func isCreatorProfile(_ profile: FamilyProfile) -> Bool {
        if profile.currentRole == MembershipRole.creator.rawValue { return true }
        return resolvedMembership(for: profile)?.hasRole(.creator) == true
    }

    private func resolvedMembership(for profile: FamilyProfile) -> HouseholdMembership? {
        profile.primaryMembership ?? viewModel.membership(for: profile)
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

    /// 详情页「角色」一行：使用 `LocalizedStringKey`，由详情页 `\.locale` 驱动翻译。
    private func detailRoleLabel(for profile: FamilyProfile) -> LocalizedStringKey {
        if profile.isVirtualUser {
            return "成员档案"
        }
        if let membership = resolvedMembership(for: profile),
           let role = membership.parsedRole {
            return role.localizedName
        }
        return "群组成员"
    }

    private var canManageHousehold: Bool {
        switch currentUserRole {
        case .creator, .admin:
            return true
        case .member:
            return false
        }
    }

    /// 只要是当前群组下「有账号」的正式成员（含 member/admin/creator）即可新建无账号成员档案。
    private var canCreateVirtualProfile: Bool {
        guard let selectedMembershipId = appRouter.selectedMembershipId else { return false }
        guard let currentMembership = viewModel.members.first(where: { $0.id == selectedMembershipId }) else { return false }
        return currentMembership.userId != nil
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
    private func renameCurrentHousehold(to newName: String, description: String) async {
        renameErrorMessage = nil
        guard let householdId = appRouter.selectedHouseholdId else {
            renameErrorMessage = AppLocalized.localized("当前未选择群组。")
            return
        }

        let renameFailureMessage = await viewModel.renameHousehold(
            householdId: householdId,
            newName: newName,
            description: description
        )
        if let renameFailureMessage {
            renameErrorMessage = renameFailureMessage
            return
        }

        await appRouter.refreshStateFromBackend()
        await appRouter.refreshSelectedHouseholdSnapshot()
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
    private func handleRequiresLoginIfNeeded() async {
        guard viewModel.requiresLogin else { return }
        if isGuestMode {
            viewModel.clearRequiresLogin()
            return
        }
        guard authSessionGuard.isLoggingOut == false else {
            viewModel.clearRequiresLogin()
            return
        }
        viewModel.clearRequiresLogin()
        await appRouter.refreshStateFromBackend()
    }

}

private struct OrganizationSettingsSheet: View {
    @Environment(\.isGuestMode) private var isGuestMode
    @EnvironmentObject private var appSettings: AppSettingsManager
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var familyViewModel: FamilyViewModel
    @State private var name: String
    @State private var groupDescription: String = ""
    @State private var showDisbandConfirmation = false
    private let initialName: String
    private let initialDescription: String
    let isSubmitting: Bool
    let canDisband: Bool
    let errorMessage: String?
    let onSubmit: @MainActor (String, String) async -> Void
    let onDisband: @MainActor (String) async -> Bool

    init(
        initialName: String,
        initialDescription: String,
        familyViewModel: FamilyViewModel,
        isSubmitting: Bool,
        canDisband: Bool,
        errorMessage: String?,
        onSubmit: @escaping @MainActor (String, String) async -> Void,
        onDisband: @escaping @MainActor (String) async -> Bool
    ) {
        self.familyViewModel = familyViewModel
        _name = State(initialValue: initialName)
        self.initialName = initialName
        self.initialDescription = initialDescription
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

    private var trimmedDescription: String {
        groupDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedInitialName: String {
        initialName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedInitialDescription: String {
        initialDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        isSubmitting == false
            && isDisbanding == false
            && trimmedName.isEmpty == false
            && (trimmedName != normalizedInitialName || trimmedDescription != normalizedInitialDescription)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 18) {
                    organizationNameField
                    organizationDescriptionField

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    saveChangesButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 0)

                if isGuestMode == false {
                    VStack(spacing: 18) {
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
                    .padding(.bottom, 28)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .onAppear {
                groupDescription = initialDescription
            }
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
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
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

    private var organizationDescriptionField: some View {
        TextField("输入群组描述（选填）…", text: $groupDescription, axis: .vertical)
            .lineLimit(3 ... 6)
            .disabled(isSubmitting || isDisbanding)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var saveChangesButton: some View {
        Button {
            let nameSnapshot = trimmedName
            let descriptionSnapshot = trimmedDescription
            Task { @MainActor in
                await onSubmit(nameSnapshot, descriptionSnapshot)
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
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        } label: {
            settingsNavigationRow(
                title: "移交群主",
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
                    Text("解散群组")
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
                        Text("退出群组")
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

    private func settingsNavigationRow(title: LocalizedStringKey, systemImage: String) -> some View {
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
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
