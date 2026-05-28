import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @EnvironmentObject private var appSettings: AppSettingsManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var groupSwitcher = GroupSwitcherCoordinator()

    var body: some View {
        Group {
            switch appRouter.appState {
            case .unauthenticated:
                LoginView()
            case .orgRouting, .householdSelection:
                HouseholdSelectionView()
            case .pendingApproval:
                PendingView()
            case .activeMember:
                AppTabRootView()
            }
        }
        .environmentObject(groupSwitcher)
        .animation(.easeInOut, value: appRouter.appState)
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
                .presentationDetents([.height(350), .medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $groupSwitcher.isShowingCreateOrganizationSheet) {
            CreateOrganizationSheet(
                organizationName: $groupSwitcher.newOrganizationName,
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
        .task {
            await appRouter.refreshStateFromBackend()
            await fetchHouseholdsAndCheckCreatorRole()
        }
        .task(id: appRouter.appState) {
            if case .activeMember = appRouter.appState {
                _ = await NotificationManager.shared.requestAuthorizationIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await appRouter.refreshStateFromBackend()
                    await fetchHouseholdsAndCheckCreatorRole()
                }
            } else if newPhase == .inactive || newPhase == .background {
                Task {
                    await preScheduleLocalNotifications()
                }
            }
        }
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
            let now = Date()
            let upcoming = tasks
                .filter { task in
                    guard let due = task.dueDate else { return false }
                    guard due > now else { return false }
                    switch task.status {
                    case .completed, .cancelled, .failed, .expired:
                        return false
                    default:
                        return true
                    }
                }
                .sorted { lhs, rhs in
                    (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
                }
                .map(TaskAlarmPayload.init(schedulingFrom:))
            await NotificationManager.shared.syncLocalNotifications(upcomingTasks: upcoming)
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
