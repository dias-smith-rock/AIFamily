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
    @State private var showOverdueSheet = false
    @State private var showCompletedSheet = false
    @State private var isShowingCreateFlexibleSheet = false
    @State private var isShowingWriteTargetPicker = false
    @State private var isShowingSearch = false
    @State private var createTaskFormInstanceID = UUID()
    @State private var currentMembershipRole: MembershipRole = .member
    @State private var completionCheckedTaskIDs: Set<UUID> = []
    @State private var completionFlyingTaskIDs: Set<UUID> = []
    @State private var completionInFlightTaskIDs: Set<UUID> = []

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
        ZStack(alignment: .bottomTrailing) {
            todoMainContent
            createTodoFAB
        }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { todoToolbar }
            .sheet(isPresented: $showCompletedSheet) { completedTasksSheet }
            .sheet(isPresented: $showOverdueSheet) { overdueTasksSheet }
            .sheet(item: $taskForDetailSheet) { task in taskDetailSheet(task: task) }
            .sheet(isPresented: $isShowingCreateFlexibleSheet) { createFlexibleSheet }
            .sheet(isPresented: $isShowingWriteTargetPicker) {
                WriteTargetHouseholdPicker { _ in
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        createTaskFormInstanceID = UUID()
                        isShowingCreateFlexibleSheet = true
                    }
                }
                .environmentObject(appRouter)
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingSearch) {
                ScheduleSearchView(
                    onOpenTask: { task in
                        taskForDetailSheet = task
                    },
                    onOpenLedger: { _ in },
                    onOpenMember: { _, householdId in
                        if let option = appRouter.selectableHouseholds.first(where: { $0.id == householdId }) {
                            appRouter.chooseHousehold(option)
                        }
                    }
                )
                .environmentObject(appRouter)
                .environment(\.locale, appSettings.appLocale)
            }
            .task(id: todoLoadTrigger) {
                bindHouseholdContext()
                guard appRouter.hasCompletedAuthBootstrap else { return }
                await viewModel.loadTasksIfNeeded()
                openPendingFlexibleTaskIfNeeded()
                await refreshCurrentMembershipRole()
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleTasksDidChange)) { _ in
                Task {
                    await scheduleViewModel.loadTasks(silent: true)
                    await viewModel.loadTasks(silent: true, force: true)
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
            GroupSwitcherToolbarButton()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel(L10n.Schedule.search)
        }
    }

    private var createTodoFAB: some View {
        Button {
            presentCreateFlexible()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(AppTheme.ColorToken.accent, in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, showsTodoSummaryFooter ? 148 : 72)
        .accessibilityLabel(L10n.Common.newToDo)
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

    private func beginCompleteFlexibleTask(_ task: FamilyTask) {
        guard completionInFlightTaskIDs.contains(task.id) == false else { return }

        completionInFlightTaskIDs.insert(task.id)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            completionCheckedTaskIDs.insert(task.id)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)

            withAnimation(.easeIn(duration: 0.52)) {
                completionFlyingTaskIDs.insert(task.id)
            }

            try? await Task.sleep(nanoseconds: 520_000_000)

            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                viewModel.applyOptimisticCompletion(for: task)
            }

            completionFlyingTaskIDs.remove(task.id)
            completionCheckedTaskIDs.remove(task.id)

            do {
                try await viewModel.completeFlexibleTask(
                    task,
                    actingMembershipId: appRouter.selectedMembershipId
                )
                await scheduleViewModel.loadTasks(silent: true)
            } catch {
                await viewModel.loadTasks(silent: true, force: true)
            }

            completionInFlightTaskIDs.remove(task.id)
        }
    }

    private var showsTodoSummaryFooter: Bool {
        viewModel.overdueTasks.isEmpty == false || viewModel.completedTasks.isEmpty == false
    }

    private var todoListScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if viewModel.mainSectionedTasks().isEmpty {
                    overdueOnlyPlaceholderContent
                } else {
                    ForEach(viewModel.mainSectionedTasks(), id: \.0.id) { section, tasks in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.titleKey)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(tasks) { task in
                                let isFlying = completionFlyingTaskIDs.contains(task.id)
                                TodoFlexibleRow(
                                    task: task,
                                    displayTitle: viewModel.displayTitle(for: task),
                                    forWhomAvatars: viewModel.forWhomAvatarSources(for: task),
                                    deadlineLabel: deadlineLabel(for: task),
                                    style: .active,
                                    isCompletionChecked: completionCheckedTaskIDs.contains(task.id),
                                    onToggleComplete: {
                                        beginCompleteFlexibleTask(task)
                                    },
                                    onOpen: {
                                        taskForDetailSheet = task
                                    }
                                )
                                .scaleEffect(isFlying ? 0.22 : 1, anchor: .center)
                                .offset(x: isFlying ? 72 : 0, y: isFlying ? 220 : 0)
                                .opacity(isFlying ? 0 : 1)
                                .zIndex(isFlying ? 2 : 0)
                                .allowsHitTesting(isFlying == false && completionInFlightTaskIDs.contains(task.id) == false)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            todoSummaryFooterInset
        }
        .refreshable {
            await viewModel.loadTasks(silent: true, force: true)
        }
    }

    private var todoSummaryFooterInset: some View {
        Group {
            if showsTodoSummaryFooter {
                todoSummaryFooterRow
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background {
                        AppTheme.ColorToken.background
                            .shadow(color: Color.black.opacity(0.08), radius: 8, y: -2)
                    }
            }
        }
    }

    private var todoSummaryFooterRow: some View {
        Group {
            if viewModel.overdueTasks.isEmpty == false || viewModel.completedTasks.isEmpty == false {
                HStack(spacing: 10) {
                    if viewModel.overdueTasks.isEmpty == false {
                        compactOverdueSummaryCard
                            .frame(maxWidth: .infinity)
                    }
                    if viewModel.completedTasks.isEmpty == false {
                        compactCompletedSummaryCard
                            .frame(maxWidth: .infinity)
                    }
                }
            }
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
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            todoSummaryFooterInset
        }
        .refreshable {
            await viewModel.loadTasks(silent: true, force: true)
        }
    }

    private var compactCompletedSummaryCard: some View {
        Button {
            showCompletedSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(
                    String(
                        format: AppLocalized.string(L10n.Common.lldToDoSCompleted, locale: locale),
                        Int64(viewModel.completedTasks.count)
                    )
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: viewModel.completedTasks.count)
            }
            .padding(.horizontal, 10)
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
            Text(L10n.Common.tapToReviewAndAdjustDeadlines.localized)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 24)
    }

    private var compactOverdueSummaryCard: some View {
        Button {
            showOverdueSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                        .font(.body)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(L10n.Todo.overdueCount.formatted(locale: locale, viewModel.overdueTasks.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
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

    private func presentCreateFlexible() {
        if appRouter.selectableHouseholds.count > 1 {
            isShowingWriteTargetPicker = true
        } else {
            createTaskFormInstanceID = UUID()
            isShowingCreateFlexibleSheet = true
        }
    }

    /// household 或 auth bootstrap 完成后触发待办加载，避免 JWT 刷新前过早请求。
    private var todoLoadTrigger: String {
        "\(appRouter.viewHouseholdIdsToken)-\(appRouter.hasCompletedAuthBootstrap)"
    }

    private func bindHouseholdContext() {
        viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
        viewModel.setViewHouseholdIds(appRouter.selectedHouseholdIds)
        scheduleViewModel.setHouseholdContext(appRouter.selectedHouseholdId)
        scheduleViewModel.setViewHouseholdIds(appRouter.selectedHouseholdIds)
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

    private func deadlineLabel(for task: FamilyTask) -> String? {
        guard let day = task.flexibleDeadlineDay else {
            return nil
        }
        let fmt = day.formatted(
            .dateTime
                .month(.defaultDigits)
                .day(.defaultDigits)
                .weekday(.abbreviated)
                .locale(locale)
        )
        return String(
            format: AppLocalized.string(L10n.Common.dueBy2, locale: locale),
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
    let deadlineLabel: (FamilyTask) -> String?
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
    let deadlineLabel: String?
    let style: Style
    var isCompletionChecked: Bool = false
    var onToggleComplete: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leadingControl

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .strikethrough(style == .completed)
                    .lineLimit(2)

                if let deadlineLabel {
                    Text(deadlineLabel)
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onOpen?()
            }

            if forWhomAvatars.isEmpty == false {
                TaskCardForWhomTrailing(sources: forWhomAvatars, style: .compact, showsEmptyPlaceholder: false)
            }
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

    @ViewBuilder
    private var leadingControl: some View {
        if style == .active, let onToggleComplete {
            Button(action: onToggleComplete) {
                Image(systemName: isCompletionChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompletionChecked ? .green : Color.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Common.markAsComplete)
            .disabled(isCompletionChecked)
        } else {
            Image(systemName: leadingSymbolName)
                .font(.subheadline)
                .foregroundStyle(leadingSymbolColor)
                .frame(width: 24)
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
