import SwiftUI

struct AppTabRootView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @State private var selectedTab: Tab = .schedule
    @StateObject private var reviewRedirectManager = ReviewRedirectManager.shared
    @State private var showAnonymousBindPrompt = false
    @State private var showAnonymousBindLinkSheet = false

    enum Tab: Hashable {
        case schedule
        case todos
        case expenses
        case location
        case settings

        var titleKey: LocalizedStringResource {
            switch self {
            case .schedule: L10n.Schedule.schedule.localized
            case .todos: L10n.Common.toDos.localized
            case .expenses: L10n.Ledger.wallet.localized
            case .location: L10n.Location.location.localized
            case .settings: L10n.Common.settingsTab.localized
            }
        }

        var systemImage: String {
            switch self {
            case .schedule: "calendar"
            case .todos: "checklist"
            case .expenses: "wallet.pass"
            case .location: "map"
            case .settings: "gearshape.2"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ScheduleMainView()
                .tabItem {
                    Label(Tab.schedule.titleKey, systemImage: Tab.schedule.systemImage)
                }
                .tag(Tab.schedule)

            TodoMainView()
                .tabItem {
                    Label(Tab.todos.titleKey, systemImage: Tab.todos.systemImage)
                }
                .tag(Tab.todos)

            ExpenseMainView()
                .tabItem {
                    Label(Tab.expenses.titleKey, systemImage: Tab.expenses.systemImage)
                }
                .tag(Tab.expenses)

            LocationMainView(isTabActive: selectedTab == .location)
                .tabItem {
                    Label(Tab.location.titleKey, systemImage: Tab.location.systemImage)
                }
                .tag(Tab.location)

            SettingsMainView()
                .tabItem {
                    Label(Tab.settings.titleKey, systemImage: Tab.settings.systemImage)
                }
                .tag(Tab.settings)
        }
        .onAppear {
            AutoLoginPerformanceTracer.finishMainPageReached(appRouter: appRouter)
            OAuthLoginPerformanceTracer.finishMainPageReached(appRouter: appRouter)
            OfflineColdStartPerformanceTracer.finishMainPageReached(appRouter: appRouter)
            GuestLoginPerformanceTracer.finishMainPageReached(appRouter: appRouter)
            if let tap = appRouter.pendingTaskReminderTap {
                selectedTab = tap.isFlexibleTodo ? .todos : .schedule
            }
            presentAnonymousBindPromptIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .anonymousBindPromptDidSchedule)) { _ in
            Task { @MainActor in
                // 等创建 Sheet 先 dismiss，再弹出绑定引导。
                try? await Task.sleep(for: .milliseconds(450))
                presentAnonymousBindPromptIfNeeded()
            }
        }
        .alert(L10n.Auth.anonymousBindPromptTitle.localized, isPresented: $showAnonymousBindPrompt) {
            Button(L10n.Auth.guestBindAccount) {
                showAnonymousBindLinkSheet = true
            }
            Button(L10n.Common.later, role: .cancel) {}
        } message: {
            Text(L10n.Auth.anonymousBindPromptMessage.localized)
        }
        .sheet(isPresented: $showAnonymousBindLinkSheet) {
            NavigationStack {
                AnonymousAccountLinkCard {
                    showAnonymousBindLinkSheet = false
                    Task { await appRouter.refreshStateFromBackend() }
                }
                .padding()
                .navigationTitle(L10n.Auth.guestBindAccount.localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.Common.close) {
                            showAnonymousBindLinkSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: appRouter.pendingTaskReminderTap) { _, newValue in
            guard let tap = newValue else { return }
            selectedTab = tap.isFlexibleTodo ? .todos : .schedule
        }
        .onChange(of: appRouter.pendingOpenGroupSettings) { _, shouldOpen in
            guard shouldOpen else { return }
            selectedTab = .settings
        }
        .reviewAlertModifier(manager: reviewRedirectManager)
        .id(appSettings.selectedLanguage.id)
    }

    private func presentAnonymousBindPromptIfNeeded() {
        guard appRouter.isAnonymousUser,
              AnonymousBindPromptStore.consumeIfPending() else {
            return
        }
        showAnonymousBindPrompt = true
    }
}

#Preview {
    AppTabRootView()
        .environmentObject(AppBootstrap())
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
        .environment(\.locale, Locale(identifier: "en"))
}
