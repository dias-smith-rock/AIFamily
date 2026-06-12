import SwiftUI

struct AppTabRootView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var selectedTab: Tab = .schedule
    @StateObject private var reviewRedirectManager = ReviewRedirectManager.shared

    enum Tab: Hashable {
        case schedule
        case todos
        case location
        case family
        case personalSettings

        var titleKey: LocalizedStringKey {
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
            if let tap = appRouter.pendingTaskReminderTap {
                selectedTab = tap.isFlexibleTodo ? .todos : .schedule
            }
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
