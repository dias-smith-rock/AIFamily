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
        .safeAreaInset(edge: .top) {
            householdBar
        }
        .sheet(isPresented: $showsAssistant) {
            AssistantSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var householdBar: some View {
        HStack {
            Menu {
                Picker(
                    "切换家庭",
                    selection: Binding<UUID?>(
                        get: { appRouter.selectedHouseholdId },
                        set: { selectedId in
                            guard
                                let selectedId,
                                let option = appRouter.selectableHouseholds.first(where: { $0.id == selectedId })
                            else {
                                return
                            }
                            chooseHousehold(option)
                        }
                    )
                ) {
                    ForEach(appRouter.selectableHouseholds) { option in
                        Text(option.name).tag(Optional(option.id))
                    }
                }

                Divider()

                Button {
                    appRouter.goToOrgRouting()
                } label: {
                    Label("创建新家庭", systemImage: "plus")
                }
                Button {
                    appRouter.goToOrgRouting()
                } label: {
                    Label("扫码加入家庭", systemImage: "qrcode.viewfinder")
                }
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前家庭")
                            .font(AppTheme.FontToken.caption)
                            .foregroundStyle(AppTheme.ColorToken.textSecondary)
                        HStack(spacing: 4) {
                            Text(appRouter.selectedHouseholdName ?? "未选择")
                                .font(AppTheme.FontToken.bodyStrong)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(AppTheme.ColorToken.surfaceMuted)
    }

    private func chooseHousehold(_ option: AppRouter.HouseholdOption) {
        appRouter.chooseHousehold(option)
    }
}

#Preview {
    AppTabRootView()
        .environmentObject(AppBootstrap())
        .environmentObject(AppRouter())
}
