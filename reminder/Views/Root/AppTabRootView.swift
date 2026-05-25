import SwiftUI

struct AppTabRootView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var selectedTab: Tab = .schedule

    enum Tab {
        case schedule
        case family
        case personalSettings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TaskListView()
                .tabItem {
                    Label("日程表", systemImage: "calendar")
                }
                .tag(Tab.schedule)

            // 「消息」Tab 延后版本开放，FeedbackFeedView 仍保留在工程中。

            FamilyView()
                .tabItem {
                    Label("群组", systemImage: "person.2")
                }
                .tag(Tab.family)

            MineView()
                .tabItem {
                    Label("我的", systemImage: "gearshape.fill")
                }
                .tag(Tab.personalSettings)
        }
    }
}

#Preview {
    AppTabRootView()
        .environmentObject(AppBootstrap())
        .environmentObject(AppRouter())
}
