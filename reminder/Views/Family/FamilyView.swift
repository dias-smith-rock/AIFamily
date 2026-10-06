import SwiftUI

struct FamilyView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator
    @ObservedObject private var authSessionGuard = AuthSessionGuard.shared
    @StateObject private var viewModel = AppViewModels.makeFamilyViewModel()
    @State private var addMemberRoute: FamilyAddMemberRoute?
    @State private var isPresentingCreateLocalProfile = false
    @State private var isShowingRenameHouseholdSheet = false
    @StateObject private var orgRoutingViewModel = AppViewModels.makeOrgRoutingViewModel()
    @State private var editingProfile: FamilyProfile?
    @State private var selectedProfileForDetail: FamilyProfile?
    @State private var profilePendingTrackedBind: FamilyProfile?
    @State private var isSortingMembers = false
    @State private var renameErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlobalHeaderView(
                    leading: {
                        Text(L10n.Family.groups.localized)
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
                            .accessibilityLabel(AppLocalized.string(L10n.Family.leaveGroup, locale: locale))
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
                canBindTrackedDevice: viewModel.canEditProfile(profile),
                onEdit: {
                    selectedProfileForDetail = nil
                    editingProfile = profile
                },
                onBindTrackedDevice: {
                    selectedProfileForDetail = nil
                    profilePendingTrackedBind = profile
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        }
        .sheet(item: $profilePendingTrackedBind) { profile in
            if let householdId = appRouter.selectedHouseholdId,
               let membershipId = appRouter.selectedMembershipId {
                BindTrackedDeviceView(
                    profile: profile,
                    householdId: householdId,
                    managerMembershipId: membershipId
                )
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
            }
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
        .alert(L10n.Common.notice, isPresented: transferSuccessToastBinding) {
            Button(L10n.Common.ok, role: .cancel) {
                viewModel.acknowledgeTransferSuccessToast()
            }
        } message: {
            Text(viewModel.transferSuccessToastMessage ?? "")
        }
        .alert(L10n.Family.areYouSureYouWantToLeaveThisGroup, isPresented: $viewModel.showLeaveConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Family.leaveGroup, role: .destructive) {
                Task { await submitLeaveHousehold() }
            }
        } message: {
            Text(L10n.Schedule.afterLoggingOutYouWillNotBeAbleToViewT.localized)
        }
        .alert(L10n.Common.notice, isPresented: $viewModel.showCreatorBlockAlert) {
            Button(L10n.Common.gotIt, role: .cancel) {}
        } message: {
            Text(L10n.Family.youAreTheCreatorOfThisGroupTransferOwner.localized)
        }
        .alert(L10n.Family.couldNotLeaveGroup, isPresented: leaveErrorAlertBinding) {
            Button(L10n.Common.gotIt, role: .cancel) {
                viewModel.acknowledgeLeaveError()
            }
        } message: {
            Text(viewModel.leaveErrorMessage ?? AppLocalized.string(L10n.Common.pleaseTryAgainLater, locale: locale))
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

    private var familyListBody: some View {
        List {
            FamilyGroupSettingsSection(
                viewModel: viewModel,
                addMemberRoute: $addMemberRoute,
                editingProfile: $editingProfile,
                selectedProfileForDetail: $selectedProfileForDetail,
                isSortingMembers: $isSortingMembers,
                isShowingRenameHouseholdSheet: $isShowingRenameHouseholdSheet,
                onOpenOrganizationSettings: openOrganizationSettings
            )
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(isSortingMembers ? .active : .inactive))
        .contentMargins(.top, 0, for: .scrollContent)
        .refreshable {
            await viewModel.loadMembers()
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

    private func detailRoleLabel(for profile: FamilyProfile) -> LocalizedStringResource {
        if profile.isVirtualUser {
            return L10n.Family.memberProfile.localized
        }
        if let membership = resolvedMembership(for: profile),
           let role = membership.parsedRole {
            return role.localizedName
        }
        return L10n.Family.groupMembers.localized
    }

    private func resolvedMembership(for profile: FamilyProfile) -> HouseholdMembership? {
        profile.primaryMembership ?? viewModel.membership(for: profile)
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
            renameErrorMessage = AppLocalized.localized(L10n.Family.noGroupIsCurrentlySelected)
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
        guard authSessionGuard.isLoggingOut == false else {
            viewModel.clearRequiresLogin()
            return
        }
        viewModel.clearRequiresLogin()
        await appRouter.refreshStateFromBackend()
    }

}

#Preview {
    FamilyView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
