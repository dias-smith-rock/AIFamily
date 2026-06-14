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
        case location
        case family
        case personalSettings

        var titleKey: LocalizedStringResource {
            switch self {
            case .schedule: L10n.Schedule.schedule.localized
            case .todos: L10n.Common.toDos.localized
            case .location: L10n.Location.location.localized
            case .family: L10n.Family.groups.localized
            case .personalSettings: L10n.Common.mine.localized
            }
        }

        var systemImage: String {
            switch self {
            case .schedule: "calendar"
            case .todos: "checklist"
            case .location: "map"
            case .family: "person.2"
            case .personalSettings: "gearshape.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TaskListView()
                .tabItem {
                    Label(Tab.schedule.titleKey, systemImage: Tab.schedule.systemImage)
                }
                .tag(Tab.schedule)

            TodoListView()
                .tabItem {
                    Label(Tab.todos.titleKey, systemImage: Tab.todos.systemImage)
                }
                .tag(Tab.todos)

            LocationMainView(isTabActive: selectedTab == .location)
                .tabItem {
                    Label(Tab.location.titleKey, systemImage: Tab.location.systemImage)
                }
                .tag(Tab.location)

            // 「消息」Tab 延后版本开放，FeedbackFeedView 仍保留在工程中。

            FamilyView()
                .tabItem {
                    Label(Tab.family.titleKey, systemImage: Tab.family.systemImage)
                }
                .tag(Tab.family)

            MineView()
                .tabItem {
                    Label(Tab.personalSettings.titleKey, systemImage: Tab.personalSettings.systemImage)
                }
                .tag(Tab.personalSettings)
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
        .alert(L10n.Auth.anonymousBindAfterGroupTitle.localized, isPresented: $showAnonymousBindPrompt) {
            Button(L10n.Auth.guestBindAccount) {
                showAnonymousBindLinkSheet = true
            }
            Button(L10n.Common.later, role: .cancel) {}
        } message: {
            Text(L10n.Auth.anonymousBindAfterGroupMessage.localized)
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
            selectedTab = .family
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
