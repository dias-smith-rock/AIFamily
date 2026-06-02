import SwiftUI

struct AppTabRootView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var selectedTab: Tab = .schedule

    enum Tab: Hashable {
        case schedule
        case todos
        case family
        case personalSettings

        var titleKey: LocalizedStringKey {
            switch self {
            case .schedule: "日程表"
            case .todos: "待办"
            case .family: "群组"
            case .personalSettings: "我的"
            }
        }

        var systemImage: String {
            switch self {
            case .schedule: "calendar"
            case .todos: "checklist"
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
