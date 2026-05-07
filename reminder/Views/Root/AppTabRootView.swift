import SwiftUI

struct AppTabRootView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var selectedTab: Tab = .schedule
    @State private var showsAssistant = false
    @State private var hideScheduleAssistantFAB = false

    enum Tab {
        case schedule
        case feedback
        case family
        case personalSettings
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                ScheduleView(onRequestAIInput: {
                    showsAssistant = true
                })
                .tabItem {
                    Label("日程表", systemImage: "calendar")
                }
                .tag(Tab.schedule)

                FeedbackFeedView()
                    .tabItem {
                        Label("消息", systemImage: "bubble.left.and.bubble.right")
                    }
                    .badge(1)
                    .tag(Tab.feedback)

                FamilyView()
                    .tabItem {
                        Label("家庭", systemImage: "person.2")
                    }
                    .tag(Tab.family)

                PersonalSettingsView()
                    .tabItem {
                        Label("我的", systemImage: "gearshape.fill")
                    }
                    .tag(Tab.personalSettings)
            }
            .onPreferenceChange(ScheduleAssistantFABVisibility.PreferenceKey.self) { shouldHide in
                hideScheduleAssistantFAB = shouldHide
            }
            .onChange(of: selectedTab) { _, tab in
                if tab != .schedule {
                    hideScheduleAssistantFAB = false
                }
            }

            if selectedTab == .schedule, hideScheduleAssistantFAB == false {
                Button {
                    showsAssistant.toggle()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 92)
            }
        }
        .sheet(isPresented: $showsAssistant) {
            AssistantSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    AppTabRootView()
        .environmentObject(AppBootstrap())
        .environmentObject(AppRouter())
}
