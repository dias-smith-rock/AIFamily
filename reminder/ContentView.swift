import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @EnvironmentObject private var appSettings: AppSettingsManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("isUserLoggedIn") private var isUserLoggedIn = false
    @AppStorage("requireFaceID") private var requireFaceID = true
    @StateObject private var groupSwitcher = GroupSwitcherCoordinator()
    @StateObject private var biometricManager = BiometricManager()
    @State private var shouldHideAppSwitcherSnapshot = false

    var body: some View {
        Group {
            rootContent
        }
        .environmentObject(groupSwitcher)
        .animation(.easeInOut, value: isUserLoggedIn)
        .animation(.easeInOut, value: biometricManager.isUnlocked)
        .alert("权限变更通知", isPresented: newCreatorAlertBinding) {
            Button("立即查看") {
                appRouter.enterNewlyAssignedCreatorHousehold()
            }
            Button("关闭", role: .cancel) {
                appRouter.dismissNewCreatorAlert()
            }
        } message: {
            if let household = appRouter.newlyAssignedHousehold {
                Text(
                    String(
                        format: String(localized: "您已成为「%@」的创建者，拥有该群组的最高管理权限。"),
                        household.displayHouseholdName
                    )
                )
            }
        }
        .sheet(isPresented: $groupSwitcher.showSwitchGroupDialog) {
            SwitchGroupSheetView(coordinator: groupSwitcher)
                .environmentObject(appRouter)
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $groupSwitcher.isShowingCreateOrganizationSheet) {
            CreateOrganizationSheet(
                organizationName: $groupSwitcher.newOrganizationName,
                organizationDescription: $groupSwitcher.newOrganizationDescription,
                inputError: $groupSwitcher.createOrganizationError,
                isSubmitting: groupSwitcher.orgRoutingViewModel.isCreating,
                onSubmit: {
                    await groupSwitcher.submitCreateOrganization(appRouter: appRouter)
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $groupSwitcher.showJoinGroupSheet) {
            JoinExistingGroupSheet(
                inviteCode: $groupSwitcher.joinCode,
                inputError: $groupSwitcher.joinInputError,
                isSubmitting: groupSwitcher.orgRoutingViewModel.isJoining,
                onScan: {
                    groupSwitcher.showJoinScanner = true
                },
                onSubmit: {
                    await groupSwitcher.submitJoinGroup(appRouter: appRouter, locale: appSettings.appLocale)
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $groupSwitcher.showJoinScanner) {
            OrganizationJoinQRScannerSheet { raw in
                if let code = groupSwitcher.firstInviteCode(from: raw.uppercased()) {
                    groupSwitcher.joinCode = code
                    groupSwitcher.joinInputError = nil
                } else {
                    groupSwitcher.joinInputError = AppLocalized.string(
                        "未识别到有效邀请码，请重试。",
                        locale: appSettings.appLocale
                    )
                }
                groupSwitcher.showJoinScanner = false
            } onError: { message in
                groupSwitcher.joinInputError = message
                groupSwitcher.showJoinScanner = false
            }
        }
        .task(id: appRouter.appState) {
            if isUserLoggedIn && biometricManager.isUnlocked {
                _ = await NotificationManager.shared.requestAuthorizationIfNeeded()
            }
        }
        .task(id: isUserLoggedIn) {
            guard isUserLoggedIn else { return }
            _ = appRouter.restoreOfflineHouseholdContextIfNeeded()
            appRouter.goToActiveMember()
            await appRouter.refreshStateFromBackend()
            await fetchHouseholdsAndCheckCreatorRole()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Self.logAppOpenedIfNeeded()
                shouldHideAppSwitcherSnapshot = false
                Task {
                    await NotificationManager.shared.clearBadgeCount()
                    guard isUserLoggedIn else { return }
                    _ = appRouter.restoreOfflineHouseholdContextIfNeeded()
                    await appRouter.refreshStateFromBackend()
                    await fetchHouseholdsAndCheckCreatorRole()
                }
            } else if newPhase == .inactive || newPhase == .background {
                shouldHideAppSwitcherSnapshot = isUserLoggedIn && biometricManager.isUnlocked
                biometricManager.lockIfNeeded()
                Task {
                    await preScheduleLocalNotifications()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskReminderNotificationTapped)) { notification in
            guard let tap = notification.object as? TaskReminderNotificationUserInfo.Tap else { return }
            Task { @MainActor in
                appRouter.preferHouseholdOnNextRefresh(tap.householdId)
                appRouter.pendingTaskReminderTap = tap
                await appRouter.refreshStateFromBackend()
                await fetchHouseholdsAndCheckCreatorRole()
                if appRouter.selectedHouseholdId != tap.householdId {
                    appRouter.consumePendingTaskReminderTap()
                    appRouter.goToHouseholdSelection()
                }
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if isUserLoggedIn == false {
            LoginView()
        } else if biometricManager.isUnlocked == false {
            LockScreenView(
                isAuthenticating: biometricManager.isAuthenticating,
                onUnlock: { biometricManager.authenticate() }
            )
            .onAppear {
                biometricManager.authenticate()
            }
        } else {
            AppTabRootView()
                .blur(radius: shouldHideAppSwitcherSnapshot ? 20 : 0)
        }
    }

    private static var hasLoggedAppOpenThisSession = false

    private static func logAppOpenedIfNeeded() {
        guard hasLoggedAppOpenThisSession == false else { return }
        hasLoggedAppOpenThisSession = true
        AnalyticsManager.log(event: .appOpened)
    }

    private var newCreatorAlertBinding: Binding<Bool> {
        Binding(
            get: { appRouter.showNewCreatorAlert },
            set: { isPresented in
                if isPresented == false {
                    appRouter.dismissNewCreatorAlert()
                }
            }
        )
    }

    @MainActor
    private func fetchHouseholdsAndCheckCreatorRole() async {
        guard appRouter.appState != .unauthenticated else { return }
        let orgViewModel = AppViewModels.makeOrgRoutingViewModel()
        await orgViewModel.fetchMyHouseholds(appRouter: appRouter)
    }

    @MainActor
    private func preScheduleLocalNotifications() async {
        guard appRouter.appState == .activeMember else { return }
        guard let householdId = appRouter.selectedHouseholdId else { return }
        do {
            let tasks = try await appBootstrap.services.taskService.fetchTasks(in: householdId)
            #if canImport(Supabase)
            var profiles: [FamilyProfile] = []
            do {
                let roster = try await SupabaseHouseholdRosterLoader.fetch(
                    in: householdId,
                    client: SupabaseManager.shared.client,
                    activeOnly: true
                )
                profiles = FamilyProfile.mergingMembershipRows(
                    roster.profiles,
                    memberships: roster.memberships
                )
            } catch {
                #if DEBUG
                print("[ContentView] preScheduleLocalNotifications roster failed: \(error.localizedDescription)")
                #endif
            }
            #else
            let profiles: [FamilyProfile] = []
            #endif
            let now = Date()
            var upcoming: [TaskAlarmPayload] = []
            var staleTaskIds: [UUID] = []

            for task in tasks {
                let payload = TaskAlarmPayload(
                    schedulingFrom: task,
                    profiles: profiles,
                    locale: appSettings.appLocale
                )
                let isUpcoming: Bool = {
                    guard let due = task.alarmAnchorDate else { return false }
                    guard due > now else { return false }
                    switch task.status {
                    case .completed, .cancelled, .failed, .expired:
                        return false
                    default:
                        return true
                    }
                }()

                if isUpcoming {
                    upcoming.append(payload)
                } else {
                    staleTaskIds.append(task.id)
                }
            }

            upcoming.sort { lhs, rhs in
                (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }

            for payload in upcoming.dropFirst(10) {
                staleTaskIds.append(payload.id)
            }

            await NotificationManager.shared.syncLocalNotifications(
                upcomingTasks: upcoming,
                cancelForTaskIds: staleTaskIds
            )
        } catch {
            #if DEBUG
            print("[ContentView] preScheduleLocalNotifications failed: \(error.localizedDescription)")
            #endif
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(AppBootstrap())
}
