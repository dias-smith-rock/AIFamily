import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appRouter.appState {
            case .unauthenticated:
                LoginView()
            case .noHousehold:
                OrgRoutingView()
            case .pendingApproval:
                PendingView()
            case .activeMember:
                MainTabView()
            }
        }
        .animation(.easeInOut, value: appRouter.appState)
        .task {
            await appRouter.refreshStateFromBackend()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                _Concurrency.Task {
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
