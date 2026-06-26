import SwiftUI

struct SettingsMainView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @EnvironmentObject private var appSettings: AppSettingsManager
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator
    @ObservedObject private var authSessionGuard = AuthSessionGuard.shared
    @StateObject private var familyViewModel = AppViewModels.makeFamilyViewModel()
    @StateObject private var mineViewModel = AppViewModels.makeMineViewModel()
    @StateObject private var orgRoutingViewModel = AppViewModels.makeOrgRoutingViewModel()
    @State private var addMemberRoute: FamilyAddMemberRoute?
    @State private var isPresentingCreateLocalProfile = false
    @State private var isShowingRenameHouseholdSheet = false
    @State private var editingProfile: FamilyProfile?
    @State private var selectedProfileForDetail: FamilyProfile?
    @State private var isSortingMembers = false
    @State private var renameErrorMessage: String?
    @State private var editingSelfProfile: FamilyProfile?
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false
    @State private var showClearGuestDataAlert = false
    @State private var isClearingGuestData = false

    var body: some View {
        settingsNavigationWithLifecycle
            .alert(L10n.Common.notice, isPresented: toastAlertBinding) {
                Button(L10n.Common.ok, role: .cancel) { mineViewModel.acknowledgeToast() }
            } message: {
                Text(verbatim: mineViewModel.toastMessage ?? "")
            }
            .alert(L10n.Common.exitFailed, isPresented: signOutErrorAlertBinding) {
                Button(L10n.Common.gotIt, role: .cancel) { mineViewModel.acknowledgeSignOutError() }
            } message: {
                Text(verbatim: mineViewModel.signOutErrorMessage ?? "")
            }
            .alert(L10n.Common.deleteAccount, isPresented: $mineViewModel.showDeleteAccountAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.deleteAccount2, role: .destructive) {
                    Task {
                        authSessionGuard.beginLoggingOut()
                        familyViewModel.prepareForSignOut()
                        await mineViewModel.deleteAccount(appRouter: appRouter)
                    }
                }
            } message: {
                Text(L10n.Family.thisOperationWillPermanentlyDeleteYourAcco.localized)
            }
            .alert(L10n.Common.cannotDeleteAccount, isPresented: $mineViewModel.showCreatorBlockAlert) {
                Button(L10n.Common.gotIt, role: .cancel) {}
                Button(L10n.Family.groupSettings) {
                    openOrganizationSettings()
                }
            } message: {
                Text(L10n.Settings.deleteAccountCreatorBlock.formatted(locale: locale, mineViewModel.creatorBlockGroupName, mineViewModel.creatorBlockGroupCount))
            }
            .personalAccountSettingsAlerts(
                viewModel: mineViewModel,
                showTermsSheet: $showTermsSheet,
                showPrivacySheet: $showPrivacySheet
            )
            .alert(L10n.Auth.clearGuestDataConfirmTitle, isPresented: $showClearGuestDataAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Auth.guestStartFreshExperience, role: .destructive) {
                    Task { await clearGuestDataAndStartOver() }
                }
            } message: {
                Text(L10n.Auth.clearGuestDataConfirmMessage.localized)
            }
    }

    private var toastAlertBinding: Binding<Bool> {
        Binding(
            get: { mineViewModel.toastMessage != nil },
            set: { if $0 == false { mineViewModel.acknowledgeToast() } }
        )
    }

    private var signOutErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { mineViewModel.signOutErrorMessage != nil },
            set: { if $0 == false { mineViewModel.acknowledgeSignOutError() } }
        )
    }

    private var settingsNavigationWithLifecycle: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlobalHeaderView(
                    leading: {
                        Text(L10n.Common.settingsTab.localized)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                    },
                    trailing: {
                        if familyViewModel.canLeaveCurrentHousehold && isMemberRole {
                            Button {
                                familyViewModel.requestToLeave()
                            } label: {
                                if familyViewModel.isLeaving {
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
                            .disabled(familyViewModel.isLeaving)
                            .accessibilityLabel(AppLocalized.string(L10n.Family.leaveGroup, locale: locale))
                        } else {
                            EmptyView()
                        }
                    }
                )

                settingsListBody
                    .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .environment(\.locale, appSettings.appLocale)
        .task {
            await mineViewModel.loadAccountSummary()
            familyViewModel.setHouseholdContext(appRouter.selectedHouseholdId)
            familyViewModel.setMembershipContext(appRouter.selectedMembershipId)
            await familyViewModel.loadMembers()
            await handleRequiresLoginIfNeeded()
            Task { await appRouter.refreshSelectedHouseholdSnapshot() }
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
            familyViewModel.setHouseholdContext(newValue)
            Task {
                await familyViewModel.loadMembers()
                await handleRequiresLoginIfNeeded()
                Task { await appRouter.refreshSelectedHouseholdSnapshot() }
            }
        }
        .onChange(of: appRouter.selectedMembershipId) { _, newValue in
            familyViewModel.setMembershipContext(newValue)
            Task { await familyViewModel.loadMembers() }
        }
        .onChange(of: familyViewModel.requiresLogin) { _, needsLogin in
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
                        guard familyViewModel.canAddMember(hasPremiumAccess: appRouter.hasPremiumAccess) else {
                            addMemberRoute = nil
                            appRouter.presentPremiumUpgrade()
                            return
                        }
                        addMemberRoute = .invite
                    },
                    onChooseCreateProfile: {
                        guard canCreateVirtualProfile else { return }
                        guard familyViewModel.canAddMember(hasPremiumAccess: appRouter.hasPremiumAccess) else {
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
                    activeMemberCount: familyViewModel.activeMemberCount,
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
                    await familyViewModel.uploadAvatar(data: data, profileId: profileId)
                },
                onSave: { householdId, draft in
                    let result = await familyViewModel.createLocalProfile(
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
                canEdit: familyViewModel.canEditProfile(profile),
                memberRemoval: memberRemovalAction(for: profile),
                adminRoleToggle: adminRoleToggleAction(for: profile),
                uploadAvatar: { data, profileId in
                    await familyViewModel.uploadAvatar(data: data, profileId: profileId)
                },
                onSave: { _, draft in
                    await familyViewModel.updateProfile(profile, draft: draft)
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        }
        .fullScreenCover(item: $selectedProfileForDetail) { profile in
            ProfileDetailView(
                profile: profile,
                roleLabel: detailRoleLabel(for: profile),
                canEdit: familyViewModel.canEditProfile(profile),
                onEdit: {
                    selectedProfileForDetail = nil
                    editingProfile = profile
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        }
        .fullScreenCover(item: $editingSelfProfile) { profile in
            ProfileEditView(
                mode: .edit(profile),
                householdId: appRouter.selectedHouseholdId,
                canEdit: familyViewModel.canEditProfile(profile),
                uploadAvatar: { data, profileId in
                    await familyViewModel.uploadAvatar(data: data, profileId: profileId)
                },
                onSave: { _, draft in
                    await familyViewModel.updateProfile(profile, draft: draft)
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        }
        .sheet(isPresented: $isShowingRenameHouseholdSheet) {
            OrganizationSettingsSheet(
                initialName: appRouter.selectedHouseholdName ?? "",
                initialDescription: appRouter.selectedHouseholdDescription,
                familyViewModel: familyViewModel,
                isSubmitting: familyViewModel.isLoading,
                canDisband: familyViewModel.canDisbandCurrentHousehold,
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
                familyViewModel.acknowledgeTransferSuccessToast()
            }
        } message: {
            Text(familyViewModel.transferSuccessToastMessage ?? "")
        }
        .alert(L10n.Family.areYouSureYouWantToLeaveThisGroup, isPresented: $familyViewModel.showLeaveConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Family.leaveGroup, role: .destructive) {
                Task { await submitLeaveHousehold() }
            }
        } message: {
            Text(L10n.Schedule.afterLoggingOutYouWillNotBeAbleToViewT.localized)
        }
        .alert(L10n.Common.notice, isPresented: $familyViewModel.showCreatorBlockAlert) {
            Button(L10n.Common.gotIt, role: .cancel) {}
        } message: {
            Text(L10n.Family.youAreTheCreatorOfThisGroupTransferOwner.localized)
        }
        .alert(L10n.Family.couldNotLeaveGroup, isPresented: leaveErrorAlertBinding) {
            Button(L10n.Common.gotIt, role: .cancel) {
                familyViewModel.acknowledgeLeaveError()
            }
        } message: {
            Text(familyViewModel.leaveErrorMessage ?? AppLocalized.string(L10n.Common.pleaseTryAgainLater, locale: locale))
        }
    }

    private var leaveErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { familyViewModel.leaveErrorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    familyViewModel.acknowledgeLeaveError()
                }
            }
        )
    }

    private var transferSuccessToastBinding: Binding<Bool> {
        Binding(
            get: { familyViewModel.transferSuccessToastMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    familyViewModel.acknowledgeTransferSuccessToast()
                }
            }
        )
    }

    private var settingsListBody: some View {
        List {
            PersonalVIPSubscriptionSection()

            FamilyGroupSettingsSection(
                viewModel: familyViewModel,
                addMemberRoute: $addMemberRoute,
                editingProfile: $editingProfile,
                selectedProfileForDetail: $selectedProfileForDetail,
                isSortingMembers: $isSortingMembers,
                isShowingRenameHouseholdSheet: $isShowingRenameHouseholdSheet,
                onOpenOrganizationSettings: openOrganizationSettings
            )

            PersonalAccountSettingsSection(
                viewModel: mineViewModel,
                familyViewModel: familyViewModel,
                editingSelfProfile: $editingSelfProfile,
                showTermsSheet: $showTermsSheet,
                showPrivacySheet: $showPrivacySheet,
                showClearGuestDataAlert: $showClearGuestDataAlert,
                isClearingGuestData: $isClearingGuestData,
                showsProfileHeader: false,
                showsInlineVIPEntry: false
            )
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(isSortingMembers ? .active : .inactive))
        .contentMargins(.top, 0, for: .scrollContent)
        .refreshable {
            await familyViewModel.loadMembers()
            await mineViewModel.loadAccountSummary()
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
        guard familyViewModel.shouldShowDeleteButton(for: profile) else { return nil }
        return ProfileEditView.MemberRemovalAction(
            buttonTitle: familyViewModel.deleteButtonTitle(for: profile),
            isVirtualMember: familyViewModel.isVirtualMember(profile),
            onDelete: { await familyViewModel.deleteOrRemoveMember(profile: profile) }
        )
    }

    private func adminRoleToggleAction(for profile: FamilyProfile) -> ProfileEditView.AdminRoleToggleAction? {
        familyViewModel.adminRoleToggleAction(for: profile)
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
        profile.primaryMembership ?? familyViewModel.membership(for: profile)
    }

    private var canCreateVirtualProfile: Bool {
        guard let selectedMembershipId = appRouter.selectedMembershipId else { return false }
        guard let currentMembership = familyViewModel.members.first(where: { $0.id == selectedMembershipId }) else { return false }
        return currentMembership.userId != nil
    }

    private var isMemberRole: Bool {
        currentUserRole == .member
    }

    private var currentUserRole: MembershipRole {
        guard
            let selectedMembershipId = appRouter.selectedMembershipId,
            let currentMembership = familyViewModel.members.first(where: { $0.id == selectedMembershipId })
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

        let renameFailureMessage = await familyViewModel.renameHousehold(
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
        let success = await familyViewModel.confirmDisband(
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
        let success = await familyViewModel.confirmLeave(householdId: householdId, appRouter: appRouter)
        guard success else { return }
        isShowingRenameHouseholdSheet = false
        await orgRoutingViewModel.fetchMyHouseholds(appRouter: appRouter)
    }

    @MainActor
    private func clearGuestDataAndStartOver() async {
        guard isClearingGuestData == false else { return }
        isClearingGuestData = true
        defer { isClearingGuestData = false }

        familyViewModel.prepareForSignOut()
        do {
            try await SupabaseAuthManager.hardSignOut(appRouter: appRouter, clearGuestArchive: true)
        } catch {
            mineViewModel.signOutErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleRequiresLoginIfNeeded() async {
        guard familyViewModel.requiresLogin else { return }
        guard authSessionGuard.isLoggingOut == false else {
            familyViewModel.clearRequiresLogin()
            return
        }
        familyViewModel.clearRequiresLogin()
        await appRouter.refreshStateFromBackend()
    }
}

#Preview {
    SettingsMainView()
        .environmentObject(AppRouter())
        .environmentObject(AppBootstrap())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
