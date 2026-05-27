import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
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
            .animation(.easeInOut, value: appRouter.appState)

            if appRouter.showNewCreatorAlert,
               let household = appRouter.newlyAssignedHousehold {
                NewCreatorAlertView(
                    householdName: household.displayHouseholdName,
                    onViewTapped: {
                        appRouter.enterNewlyAssignedCreatorHousehold()
                    },
                    onClose: {
                        appRouter.dismissNewCreatorAlert()
                    }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: appRouter.showNewCreatorAlert)
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
}
