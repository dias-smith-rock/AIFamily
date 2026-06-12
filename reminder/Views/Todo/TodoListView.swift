import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

/// 灵活待办 Tab：`task_type == flexible`，按截止日分组，点击编辑分配时间。
struct TodoListView: View {
    @Environment(\.locale) private var locale
    @Environment(\.isGuestMode) private var isGuestMode
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator
    @StateObject private var viewModel = AppViewModels.makeTodoListViewModel()
    @StateObject private var scheduleViewModel = AppViewModels.makeScheduleViewModel()

    @State private var taskForDetailSheet: FamilyTask?
    @State private var showOverdueSheet = false
    @State private var showCompletedSheet = false
    @State private var isShowingCreateFlexibleSheet = false
    @State private var createTaskFormInstanceID = UUID()
    @State private var currentMembershipRole: MembershipRole = .member

    var body: some View {
        NavigationStack {
            todoStackContent
        }
        .appLocaleEnvironment(using: appSettings)
    }

    @ViewBuilder
    private var todoMainContent: some View {
        if viewModel.isLoading {
            ProgressView(L10n.Schedule.loadingTasks.localized)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = viewModel.errorMessage {
            ContentUnavailableView {
                Label(L10n.Common.loading.localized, systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button(L10n.Common.reload) {
                    Task { await viewModel.loadTasks(force: true) }
                }
            }
        } else if viewModel.hasOpenFlexibleTasks == false {
            if viewModel.completedTasks.isEmpty {
                ContentUnavailableView {
                    Label(L10n.Common.noToDosYet.localized, systemImage: "checklist")
                } description: {
                    Text(L10n.Schedule.addTasksWithoutASetStartTimeCompleteThem.localized)
                } actions: {
                    Button(L10n.Common.newToDo) {
                        presentCreateFlexible()
                    }
                }
            } else {
                completedOnlyScrollView
            }
        } else {
            todoListScrollView
        }
    }

    private var todoStackContent: some View {
        todoMainContent
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle(L10n.Common.toDos.localized)
            .toolbar { todoToolbar }
            .sheet(isPresented: $showCompletedSheet) { completedTasksSheet }
            .sheet(isPresented: $showOverdueSheet) { overdueTasksSheet }
            .sheet(item: $taskForDetailSheet) { task in taskDetailSheet(task: task) }
            .sheet(isPresented: $isShowingCreateFlexibleSheet) { createFlexibleSheet }
            .task(id: appRouter.selectedHouseholdId) {
                bindHouseholdContext()
                await viewModel.loadTasksIfNeeded()
                openPendingFlexibleTaskIfNeeded()
                Task { await refreshCurrentMembershipRole() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleTasksDidChange)) { _ in
                Task {
                    await scheduleViewModel.loadTasks(silent: true)
                }
            }
            .onChange(of: appRouter.pendingTaskReminderTap) { _, _ in
                openPendingFlexibleTaskIfNeeded()
            }
            .onChange(of: viewModel.flexibleTasks) { _, _ in
                openPendingFlexibleTaskIfNeeded()
            }
    }

    @ToolbarContentBuilder
    private var todoToolbar: some ToolbarContent {
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
            .accessibilityLabel(L10n.Common.newToDo)
        }
    }

    private var completedTasksSheet: some View {
        CompletedTasksListView(
            tasks: viewModel.completedTasks,
            displayTitle: { viewModel.displayTitle(for: $0) },
            forWhomAvatars: { viewModel.forWhomAvatarSources(for: $0) },
            completedLabel: { completedLabel(for: $0) },
            onSelectTask: { task in
                showCompletedSheet = false
                taskForDetailSheet = task
            }
        )
        .environment(\.locale, appSettings.appLocale)
        .environment(\.layoutDirection, appSettings.layoutDirection)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var overdueTasksSheet: some View {
        OverdueTasksListView(
            tasks: viewModel.overdueTasks,
            displayTitle: { viewModel.displayTitle(for: $0) },
            forWhomAvatars: { viewModel.forWhomAvatarSources(for: $0) },
            deadlineLabel: { deadlineLabel(for: $0) },
            onSelectTask: { task in
                showOverdueSheet = false
                taskForDetailSheet = task
            }
        )
        .environment(\.locale, appSettings.appLocale)
        .environment(\.layoutDirection, appSettings.layoutDirection)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func taskDetailSheet(task: FamilyTask) -> some View {
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

    private var createFlexibleSheet: some View {
        EditTaskView(
            formMode: .flexible,
            onSaveSuccess: { _ in
                Task {
                    await viewModel.loadTasks(silent: true, force: true)
                    await scheduleViewModel.loadTasks(silent: true)
                }
            },
            onAlarmSync: { task in
                scheduleViewModel.syncAlarms(for: task)
            }
        )
        .id(createTaskFormInstanceID)
        .environmentObject(appRouter)
        .presentationDetents([.large])
    }

    // MARK: - Notification deep link

    @MainActor
    private func openPendingFlexibleTaskIfNeeded() {
        guard let pending = appRouter.pendingTaskReminderTap else { return }
        guard pending.isFlexibleTodo else { return }
        guard appRouter.selectedHouseholdId == pending.householdId else { return }
        guard let task = viewModel.flexibleTasks.first(where: { $0.id == pending.taskId }) else {
            // 组织已匹配且任务列表已更新，但目标任务不存在：留在组织主页，清空深链状态。
            appRouter.consumePendingTaskReminderTap()
            return
        }

        taskForDetailSheet = task
        appRouter.consumePendingTaskReminderTap()
    }

    private var todoListScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if viewModel.overdueTasks.isEmpty == false {
                    overdueWarningBanner
                }

                if viewModel.completedTasks.isEmpty == false {
                    completedTasksBanner
                }

                if viewModel.mainSectionedTasks().isEmpty {
                    overdueOnlyPlaceholderContent
                } else {
                    ForEach(viewModel.mainSectionedTasks(), id: \.0.id) { section, tasks in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.titleKey)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(tasks) { task in
                                TodoFlexibleRow(
                                    task: task,
                                    displayTitle: viewModel.displayTitle(for: task),
                                    forWhomAvatars: viewModel.forWhomAvatarSources(for: task),
                                    deadlineLabel: deadlineLabel(for: task),
                                    style: .active
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    taskForDetailSheet = task
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.loadTasks(silent: true, force: true)
        }
    }

    private var completedOnlyScrollView: some View {
        ScrollView {
            VStack(spacing: 20) {
                ContentUnavailableView {
                    Label(L10n.Common.noToDosYet.localized, systemImage: "checklist")
                } description: {
                    Text(L10n.Common.allActiveToDosAreDoneViewYourHistoryBel.localized)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                completedTasksBanner
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.loadTasks(silent: true, force: true)
        }
    }

    private var completedTasksBanner: some View {
        Button {
            showCompletedSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        String(
                            format: AppLocalized.string(L10n.Common.lldToDoSCompleted, locale: locale),
                            Int64(viewModel.completedTasks.count)
                        )
                    )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(L10n.Common.tapToViewCompletedItems.localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.green.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Common.viewCompletedToDos)
    }

    private var overdueOnlyPlaceholderContent: some View {
        ContentUnavailableView {
            Label(L10n.Common.nothingDueSoon.localized, systemImage: "checklist")
        } description: {
            Text(L10n.Common.allOpenToDosAreOverdueTapTheBannerAbove.localized)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 24)
    }

    private var overdueWarningBanner: some View {
        Button {
            showOverdueSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .font(.body)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Todo.overdueCount.formatted(locale: locale, viewModel.overdueTasks.count))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(L10n.Common.tapToReviewAndAdjustDeadlines.localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
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
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Schedule.viewOverdueTasks)
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
        .accessibilityLabel(L10n.Family.group.formatted(locale: locale, GroupSwitcherData.currentName(for: appRouter)))
    }

    private func presentCreateFlexible() {
        createTaskFormInstanceID = UUID()
        isShowingCreateFlexibleSheet = true
    }

    private func bindHouseholdContext() {
        viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
        scheduleViewModel.setHouseholdContext(appRouter.selectedHouseholdId)
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
        if isGuestMode {
            currentMembershipRole = .creator
            return
        }
        if await NetworkMonitor.shared.isConnected == false,
           let householdId = appRouter.selectedHouseholdId,
           let cachedRole = await HouseholdLocalCache.membershipRole(for: membershipId, in: householdId) {
            currentMembershipRole = cachedRole
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

    private func completedLabel(for task: FamilyTask) -> String {
        let fmt = task.updatedAt.formatted(
            .dateTime
                .year()
                .month(.defaultDigits)
                .day(.defaultDigits)
                .hour(.defaultDigits(amPM: .omitted))
                .minute(.defaultDigits)
                .locale(locale)
        )
        return String(
            format: AppLocalized.string(L10n.Common.completedOn, locale: locale),
            fmt
        )
    }

    private func deadlineLabel(for task: FamilyTask) -> String {
        guard let day = task.flexibleDeadlineDay else {
            return AppLocalized.string(L10n.Common.noDueDate, locale: locale)
        }
        let fmt = day.formatted(
            .dateTime
                .month(.defaultDigits)
                .day(.defaultDigits)
                .weekday(.abbreviated)
                .locale(locale)
        )
        return String(
            format: AppLocalized.string(L10n.Common.dueBy, locale: locale),
            fmt
        )
    }
}

// MARK: - Completed sheet

private struct CompletedTasksListView: View {
    @Environment(\.dismiss) private var dismiss

    let tasks: [FamilyTask]
    let displayTitle: (FamilyTask) -> String
    let forWhomAvatars: (FamilyTask) -> [TaskCardAvatarSource]
    let completedLabel: (FamilyTask) -> String
    let onSelectTask: (FamilyTask) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if tasks.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.Common.noCompletedToDos.localized, systemImage: "checkmark.circle")
                    } description: {
                        Text(L10n.Common.completedToDosWillAppearHere.localized)
                    }
                } else {
                    List {
                        ForEach(tasks) { task in
                            Button {
                                onSelectTask(task)
                            } label: {
                                TodoFlexibleRow(
                                    task: task,
                                    displayTitle: displayTitle(task),
                                    forWhomAvatars: forWhomAvatars(task),
                                    deadlineLabel: completedLabel(task),
                                    style: .completed
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle(L10n.Common.completed.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Overdue sheet

private struct OverdueTasksListView: View {
    @Environment(\.dismiss) private var dismiss

    let tasks: [FamilyTask]
    let displayTitle: (FamilyTask) -> String
    let forWhomAvatars: (FamilyTask) -> [TaskCardAvatarSource]
    let deadlineLabel: (FamilyTask) -> String
    let onSelectTask: (FamilyTask) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(tasks) { task in
                    Button {
                        onSelectTask(task)
                    } label: {
                        TodoFlexibleRow(
                            task: task,
                            displayTitle: displayTitle(task),
                            forWhomAvatars: forWhomAvatars(task),
                            deadlineLabel: deadlineLabel(task),
                            style: .overdue
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle(L10n.Common.overdue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct TodoFlexibleRow: View {
    enum Style {
        case active
        case overdue
        case completed
    }

    let task: FamilyTask
    let displayTitle: String
    let forWhomAvatars: [TaskCardAvatarSource]
    let deadlineLabel: String
    let style: Style

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: leadingSymbolName)
                .font(.subheadline)
                .foregroundStyle(leadingSymbolColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .strikethrough(style == .completed)
                    .lineLimit(2)

                Text(deadlineLabel)
                    .font(.caption)
                    .foregroundStyle(subtitleColor)
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
                .stroke(cardBorderColor, lineWidth: 1)
        }
    }

    private var cardBorderColor: Color {
        switch style {
        case .completed:
            return Color.green.opacity(0.45)
        case .active, .overdue:
            return Color.gray.opacity(0.25)
        }
    }

    private var leadingSymbolName: String {
        switch style {
        case .completed:
            return "checkmark.circle.fill"
        case .active, .overdue:
            return "flag.fill"
        }
    }

    private var leadingSymbolColor: Color {
        switch style {
        case .overdue:
            return .red
        case .completed:
            return .green
        case .active:
            return Color.accentColor
        }
    }

    private var titleColor: Color {
        style == .completed ? .secondary : .primary
    }

    private var subtitleColor: Color {
        switch style {
        case .overdue:
            return .red
        case .completed, .active:
            return .secondary
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
