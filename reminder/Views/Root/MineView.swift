import SwiftUI

struct MineView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @EnvironmentObject private var appSettings: AppSettingsManager
    @ObservedObject private var authSessionGuard = AuthSessionGuard.shared
    @StateObject private var viewModel = AppViewModels.makeMineViewModel()
    @StateObject private var familyViewModel = AppViewModels.makeFamilyViewModel()
    @State private var editingSelfProfile: FamilyProfile?
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false
    @State private var showClearGuestDataAlert = false
    @State private var isClearingGuestData = false

    var body: some View {
        mineNavigationWithLifecycle
            .alert(L10n.Common.notice, isPresented: toastAlertBinding) {
                Button(L10n.Common.ok, role: .cancel) { viewModel.acknowledgeToast() }
            } message: {
                Text(verbatim: viewModel.toastMessage ?? "")
            }
            .alert(L10n.Common.exitFailed, isPresented: signOutErrorAlertBinding) {
                Button(L10n.Common.gotIt, role: .cancel) { viewModel.acknowledgeSignOutError() }
            } message: {
                Text(verbatim: viewModel.signOutErrorMessage ?? "")
            }
            .alert(L10n.Common.deleteAccount, isPresented: $viewModel.showDeleteAccountAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.deleteAccount2, role: .destructive) {
                    Task {
                        authSessionGuard.beginLoggingOut()
                        familyViewModel.prepareForSignOut()
                        await viewModel.deleteAccount(appRouter: appRouter)
                    }
                }
            } message: {
                Text(L10n.Family.thisOperationWillPermanentlyDeleteYourAcco.localized)
            }
            .alert(L10n.Common.cannotDeleteAccount, isPresented: $viewModel.showCreatorBlockAlert) {
                Button(L10n.Common.gotIt, role: .cancel) {}
                Button(L10n.Family.groupSettings) {
                    appRouter.requestOpenGroupSettings()
                }
            } message: {
                Text(L10n.Settings.deleteAccountCreatorBlock.formatted(locale: locale, viewModel.creatorBlockGroupName, viewModel.creatorBlockGroupCount))
            }
            .personalAccountSettingsAlerts(
                viewModel: viewModel,
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
            get: { viewModel.toastMessage != nil },
            set: { if $0 == false { viewModel.acknowledgeToast() } }
        )
    }

    private var signOutErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.signOutErrorMessage != nil },
            set: { if $0 == false { viewModel.acknowledgeSignOutError() } }
        )
    }

    private var mineNavigationWithLifecycle: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlobalHeaderView {
                    Text(L10n.Common.mine.localized)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                }

                mineSettingsList
            }
            .background(AppTheme.ColorToken.background)
            .navigationBarHidden(true)
        }
        .environment(\.locale, appSettings.appLocale)
        .task {
            await viewModel.loadAccountSummary()
            familyViewModel.setHouseholdContext(appRouter.selectedHouseholdId)
            familyViewModel.setMembershipContext(appRouter.selectedMembershipId)
            await familyViewModel.loadMembers()
            await handleRequiresLoginIfNeeded()
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
            familyViewModel.setHouseholdContext(newValue)
            Task {
                await familyViewModel.loadMembers()
                await handleRequiresLoginIfNeeded()
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
        .fullScreenCover(item: $editingSelfProfile) { profile in
            ProfileEditView(
                mode: .edit(profile),
                householdId: appRouter.selectedHouseholdId,
                canEdit: familyViewModel.canEditProfile(profile),
                uploadAvatar: { data, profileId in
                    #if DEBUG
                    print("🔎 [MineDebug] uploadAvatar bytes=\(data.count)")
                    #endif
                    return await familyViewModel.uploadAvatar(data: data, profileId: profileId)
                },
                onSave: { _, draft in
                    await familyViewModel.updateProfile(profile, draft: draft)
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        }
    }

    private var mineSettingsList: some View {
        List {
            PersonalAccountSettingsSection(
                viewModel: viewModel,
                familyViewModel: familyViewModel,
                editingSelfProfile: $editingSelfProfile,
                showTermsSheet: $showTermsSheet,
                showPrivacySheet: $showPrivacySheet,
                showClearGuestDataAlert: $showClearGuestDataAlert,
                isClearingGuestData: $isClearingGuestData
            )
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .contentMargins(.top, 0, for: .scrollContent)
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
            viewModel.signOutErrorMessage = error.localizedDescription
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
    MineView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
}
