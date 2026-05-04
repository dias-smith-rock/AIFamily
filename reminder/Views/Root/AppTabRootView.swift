import SwiftUI

struct AppTabRootView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var selectedTab: Tab = .schedule
    @State private var showsAssistant = false
    @State private var showsHouseholdSwitcher = false
    @State private var showsRecentHouseholdsQuickSwitch = false

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
        .safeAreaInset(edge: .top) {
            householdBar
        }
        .sheet(isPresented: $showsAssistant) {
            AssistantSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsHouseholdSwitcher) {
            HouseholdSwitcherSheet(
                options: appRouter.selectableHouseholds,
                selectedHouseholdId: appRouter.selectedHouseholdId,
                onSelect: { option in
                    chooseHousehold(option)
                },
                onRefresh: {
                    Task {
                        await appRouter.refreshStateFromBackend()
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "最近家庭",
            isPresented: $showsRecentHouseholdsQuickSwitch,
            titleVisibility: .visible
        ) {
            ForEach(Array(appRouter.recentHouseholds.prefix(5))) { option in
                Button(option.name) {
                    chooseHousehold(option)
                }
            }
            Button("查看全部家庭") {
                showsHouseholdSwitcher = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("长按切换按钮可直接进入最近使用的家庭。")
        }
    }

    private var householdBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("当前家庭")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(appRouter.selectedHouseholdName ?? "未选择")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                showsHouseholdSwitcher = true
            } label: {
                Label("切换", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(appRouter.selectableHouseholds.count <= 1)
            .opacity(appRouter.selectableHouseholds.count <= 1 ? 0.5 : 1)
            .onLongPressGesture(minimumDuration: 0.35) {
                guard appRouter.recentHouseholds.count > 1 else { return }
                showsRecentHouseholdsQuickSwitch = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func chooseHousehold(_ option: AppRouter.HouseholdOption) {
        appRouter.chooseHousehold(option)
        showsHouseholdSwitcher = false
        showsRecentHouseholdsQuickSwitch = false
    }
}

private struct HouseholdSwitcherSheet: View {
    let options: [AppRouter.HouseholdOption]
    let selectedHouseholdId: UUID?
    let onSelect: (AppRouter.HouseholdOption) -> Void
    let onRefresh: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if options.isEmpty {
                    ContentUnavailableView(
                        "暂无可切换家庭",
                        systemImage: "person.3.sequence",
                        description: Text("请下拉刷新或稍后重试。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(options) { option in
                                Button {
                                    onSelect(option)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(option.name)
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(option.id.uuidString)
                                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if option.id == selectedHouseholdId {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .navigationTitle("切换家庭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新") {
                        onRefresh()
                    }
                }
            }
        }
    }
}

#Preview {
    AppTabRootView()
        .environmentObject(AppBootstrap())
        .environmentObject(AppRouter())
}
