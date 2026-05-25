import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appRouter: AppRouter
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
            }
        }
    }

    @MainActor
    private func fetchHouseholdsAndCheckCreatorRole() async {
        guard appRouter.appState != .unauthenticated else { return }
        let orgViewModel = AppViewModels.makeOrgRoutingViewModel()
        await orgViewModel.fetchMyHouseholds(appRouter: appRouter)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppRouter())
}
