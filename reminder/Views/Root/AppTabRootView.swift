import SwiftUI

struct AppTabRootView: View {
    @Environment(\.locale) private var locale
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
                    Label(AppLocalized.string("日程表", locale: locale), systemImage: "calendar")
                }
                .tag(Tab.schedule)

            // 「消息」Tab 延后版本开放，FeedbackFeedView 仍保留在工程中。

            FamilyView()
                .tabItem {
                    Label(AppLocalized.string("群组", locale: locale), systemImage: "person.2")
                }
                .tag(Tab.family)

            MineView()
                .tabItem {
                    Label(AppLocalized.string("我的", locale: locale), systemImage: "gearshape.fill")
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
