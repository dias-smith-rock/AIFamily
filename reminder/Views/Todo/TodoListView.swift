import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

/// 灵活待办 Tab：`task_type == flexible`，按截止日分组，点击编辑分配时间。
struct TodoListView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator
    @StateObject private var viewModel = AppViewModels.makeTodoListViewModel()
    @StateObject private var scheduleViewModel = AppViewModels.makeScheduleViewModel()

    @State private var taskForDetailSheet: FamilyTask?
    @State private var isShowingCreateFlexibleSheet = false
    @State private var createTaskFormInstanceID = UUID()
    @State private var currentMembershipRole: MembershipRole = .member

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView(AppLocalized.string("正在加载任务...", locale: locale))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label(AppLocalized.string("加载失败", locale: locale), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button(AppLocalized.string("重新加载", locale: locale)) {
                            Task { await reload() }
                        }
                    }
                } else if viewModel.flexibleTasks.isEmpty {
                    ContentUnavailableView {
                        Label(AppLocalized.string("暂无待办", locale: locale), systemImage: "checklist")
                    } description: {
                        Text(AppLocalized.string("添加没有具体开始时间的任务，在截止日前完成即可。", locale: locale))
                    } actions: {
                        Button(AppLocalized.string("新建待办", locale: locale)) {
                            presentCreateFlexible()
                        }
                    }
                } else {
                    todoListContent
                }
            }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle("待办")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    groupSwitcherMenuButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentCreateFlexible()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                    }
                    .accessibilityLabel("新建待办")
                }
            }
            .sheet(item: $taskForDetailSheet) { task in
                NavigationStack {
                    TaskDetailView(
                        initialTask: task,
                        currentUserRole: currentMembershipRole,
                        assigneeDisplayName: assigneeLabel(for: task),
                        scheduleViewModel: scheduleViewModel
                    )
                    .environmentObject(appRouter)
                }
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingCreateFlexibleSheet) {
                EditTaskView(
                    formMode: .flexible,
                    onSaveSuccess: { _ in
                        Task {
                            await reload()
                            await scheduleViewModel.loadTasks()
                        }
                    },
                    onAlarmSync: { task in
                        scheduleViewModel.syncAlarms(for: task)
                    }
                )
                .id(createTaskFormInstanceID)
                .environmentObject(appRouter)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .task {
                bindHouseholdContext()
                await refreshCurrentMembershipRole()
                await reload()
            }
            .onChange(of: appRouter.selectedHouseholdId) { _, _ in
                bindHouseholdContext()
                Task {
                    await refreshCurrentMembershipRole()
                    await reload()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleTasksDidChange)) { _ in
                Task {
                    await reload()
                    await scheduleViewModel.loadTasks(silent: true)
                }
            }
        }
        .appLocaleEnvironment(using: appSettings)
    }

    private var todoListContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.sectionedTasks(), id: \.0.id) { section, tasks in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.titleKey)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(section == TodoListViewModel.TodoSection.overdue ? .red : .secondary)

                        ForEach(tasks) { task in
                            TodoFlexibleRow(
                                task: task,
                                displayTitle: viewModel.displayTitle(for: task),
                                forWhomAvatars: viewModel.forWhomAvatarSources(for: task),
                                deadlineLabel: deadlineLabel(for: task),
                                isOverdue: section == .overdue
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                taskForDetailSheet = task
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
        .refreshable {
            await reload()
        }
    }

    private var groupSwitcherMenuButton: some View {
        Button {
            groupSwitcher.showSwitchGroupDialog = true
        } label: {
            HStack(spacing: 4) {
                Text(GroupSwitcherData.currentName(for: appRouter))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .accessibilityLabel("群组，\(GroupSwitcherData.currentName(for: appRouter))")
    }

    private func presentCreateFlexible() {
        createTaskFormInstanceID = UUID()
        isShowingCreateFlexibleSheet = true
    }

    private func bindHouseholdContext() {
        viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
        scheduleViewModel.setHouseholdContext(appRouter.selectedHouseholdId)
    }

    private func reload() async {
        await viewModel.loadTasks()
    }

    #if canImport(Supabase)
    private struct MembershipRoleRow: Decodable {
        let role: MembershipRole
    }
    #endif

    private func refreshCurrentMembershipRole() async {
        guard let membershipId = appRouter.selectedMembershipId else {
            currentMembershipRole = .member
            return
        }
        #if canImport(Supabase)
        do {
            let rows: [MembershipRoleRow] = try await SupabaseManager.shared.client
                .from("household_memberships")
                .select("role")
                .eq("id", value: membershipId.uuidString)
                .limit(1)
                .execute()
                .value
            currentMembershipRole = rows.first?.role ?? .member
        } catch {
            currentMembershipRole = .member
        }
        #else
        currentMembershipRole = .member
        #endif
    }

    private func assigneeLabel(for task: FamilyTask) -> String {
        scheduleViewModel.assigneeLabel(for: task, locale: locale)
    }

    private func deadlineLabel(for task: FamilyTask) -> String {
        guard let day = task.flexibleDeadlineDay else {
            return AppLocalized.string("未设截止日", locale: locale)
        }
        let fmt = day.formatted(
            .dateTime
                .month(.defaultDigits)
                .day(.defaultDigits)
                .weekday(.abbreviated)
                .locale(locale)
        )
        return String(
            format: AppLocalized.string("%@前", locale: locale),
            fmt
        )
    }
}

// MARK: - Row

private struct TodoFlexibleRow: View {
    let task: FamilyTask
    let displayTitle: String
    let forWhomAvatars: [TaskCardAvatarSource]
    let deadlineLabel: String
    let isOverdue: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "flag.fill")
                .font(.subheadline)
                .foregroundStyle(isOverdue ? .red : Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(deadlineLabel)
                    .font(.caption)
                    .foregroundStyle(isOverdue ? .red : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TaskCardForWhomTrailing(sources: forWhomAvatars, style: .compact)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        }
    }
}

#if DEBUG
#Preview {
    TodoListView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
#endif
