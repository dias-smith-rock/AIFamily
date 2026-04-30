import SwiftUI

struct AppTabRootView: View {
    @State private var selectedTab: Tab = .schedule
    @State private var showsAssistant = false

    enum Tab {
        case schedule
        case feedback
        case family
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
            }

            if selectedTab == .schedule {
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
}
