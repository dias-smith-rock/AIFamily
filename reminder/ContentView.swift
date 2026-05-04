import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appRouter.appState {
            case .unauthenticated:
                LoginView()
            case .orgRouting:
                OrgRoutingView()
            case .householdSelection:
                HouseholdPickerView()
            case .pendingApproval:
                PendingView()
            case .activeMember:
                AppTabRootView()
            }
        }
        .animation(.easeInOut, value: appRouter.appState)
        .task {
            await appRouter.refreshStateFromBackend()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await appRouter.refreshStateFromBackend()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppRouter())
}
