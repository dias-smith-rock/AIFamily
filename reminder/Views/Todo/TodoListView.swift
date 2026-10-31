import SwiftUI

/// 灵活待办 Tab：`task_type == flexible`，按截止日分组，点击编辑分配时间。
struct TodoListView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator
    @StateObject private var viewModel = AppViewModels.makeTodoListViewModel()
    @StateObject private var scheduleViewModel = AppViewModels.makeScheduleViewModel()

    @State private var taskForEditSheet: FamilyTask?
    @State private var showOverdueSheet = false
    @State private var showCompletedSheet = false
    @State private var isShowingCreateFlexibleSheet = false
    @State private var isShowingWriteTargetPicker = false
    @State private var isShowingSearch = false
    @State private var isShowingBackgroundSettings = false
    @State private var createTaskFormInstanceID = UUID()
    @State private var completionCheckedTaskIDs: Set<UUID> = []
    @State private var completionFlyingTaskIDs: Set<UUID> = []
    @State private var completionInFlightTaskIDs: Set<UUID> = []
    @AppStorage("todo_display_mode") private var displayModeRaw: String = TodoDisplayMode.list.rawValue

    private var displayMode: TodoDisplayMode {
        TodoDisplayMode(rawValue: displayModeRaw) ?? .list
    }

    var body: some View {
        NavigationStack {
            todoStackContent
        }
        .appLocaleEnvironment(using: appSettings)
    }

    @ViewBuilder
    private var todoMainContent: some View {
        if viewModel.isLoading {
            pullToRefreshScrollContainer {
                ProgressView(L10n.Schedule.loadingTasks.localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let message = viewModel.errorMessage {
            pullToRefreshScrollContainer {
                ContentUnavailableView {
                    Label(L10n.Common.loading.localized, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button(L10n.Common.reload) {
                        Task { await viewModel.loadTasks(force: true) }
                    }
                }
            }
        } else if viewModel.hasOpenFlexibleTasks == false {
            if viewModel.completedTasks.isEmpty {
                pullToRefreshScrollContainer {
                    ContentUnavailableView {
                        Label(L10n.Common.noToDosYet.localized, systemImage: "checklist")
                    } description: {
                        Text(L10n.Schedule.addTasksWithoutASetStartTimeCompleteThem.localized)
                    } actions: {
                        Button(L10n.Common.newToDo) {
                            AnalyticsManager.logEmptyStateCTATapped(
                                surface: AnalyticsManager.EmptyStateSurface.todo,
                                cta: AnalyticsManager.EmptyStateCTA.create
                            )
                            presentCreateFlexible()
                        }
                    }
                }
            } else {
                completedOnlyScrollView
            }
        } else if displayMode == .sticky {
            todoStickyBoardScrollView
        } else {
            todoListScrollView
        }
    }

    private var todoStackContent: some View {
        ZStack(alignment: .bottomTrailing) {
            todoMainContent
            createTodoFAB
        }
            .schedulePageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { todoToolbar }
            .sheet(isPresented: $isShowingBackgroundSettings) {
                ScheduleBackgroundSettingsSheet()
                    .environmentObject(appSettings)
            }
            .sheet(isPresented: $showCompletedSheet) { completedTasksSheet }
            .sheet(isPresented: $showOverdueSheet) { overdueTasksSheet }
            .sheet(item: $taskForEditSheet) { task in editFlexibleSheet(task: task) }
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
                    onOpenTask: { _ in },
                    onOpenLedger: { _ in },
                    onOpenMember: { _, householdId in
                        if let option = appRouter.selectableHouseholds.first(where: { $0.id == householdId }) {
                            appRouter.chooseHousehold(option)
                        }
                    }
                )
                .environmentObject(appRouter)
                .environmentObject(appSettings)
                .environment(\.locale, appSettings.appLocale)
            }
            .task(id: todoLoadTrigger) {
                bindHouseholdContext()
                guard appRouter.hasCompletedAuthBootstrap else { return }
                await viewModel.loadTasksIfNeeded()
                openPendingFlexibleTaskIfNeeded()
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
            HStack(spacing: 12) {
                Button {
                    isShowingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel(L10n.Schedule.search)
                todoOptionsMenu
            }
        }
    }

    private var todoOptionsMenu: some View {
        Menu {
            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayModeRaw = TodoDisplayMode.list.rawValue
                    }
                } label: {
                    HStack {
                        Text(L10n.Todo.showAsList)
                        Spacer(minLength: 8)
                        if displayMode == .list {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayModeRaw = TodoDisplayMode.sticky.rawValue
                    }
                } label: {
                    HStack {
                        Text(L10n.Todo.showAsStickyNotes)
                        Spacer(minLength: 8)
                        if displayMode == .sticky {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Section {
                Button {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(80))
                        isShowingBackgroundSettings = true
                    }
                } label: {
                    Label {
                        Text(L10n.Schedule.background)
                    } icon: {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
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
        .padding(.bottom, showsCreateTodoFABBottomPadding ? 96 : 20)
        .accessibilityLabel(L10n.Common.newToDo)
    }

    private var showsCreateTodoFABBottomPadding: Bool {
        displayMode == .list && showsTodoSummaryFooter
    }

    private var completedTasksSheet: some View {
        CompletedTasksListView(
            tasks: viewModel.completedTasks,
            displayTitle: { viewModel.displayTitle(for: $0) },
            forWhomAvatars: { viewModel.forWhomAvatarSources(for: $0) },
            taskHasAttachments: { viewModel.taskHasAttachments($0) },
            completedLabel: { completedLabel(for: $0) },
            onSelectTask: { task in
                showCompletedSheet = false
                taskForEditSheet = task
            }
        )
        .environment(\.locale, appSettings.appLocale)
        .environment(\.layoutDirection, appSettings.layoutDirection)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var overdueTasksSheet: some View {
        OverdueTasksListView(
            tasks: viewModel.trashBinTasks,
            displayTitle: { viewModel.displayTitle(for: $0) },
            forWhomAvatars: { viewModel.forWhomAvatarSources(for: $0) },
            taskHasAttachments: { viewModel.taskHasAttachments($0) },
            deadlineLabel: { deadlineLabel(for: $0) },
            onSelectTask: { task in
                showOverdueSheet = false
                taskForEditSheet = task
            },
            onClearTrash: {
                Task { @MainActor in
                    do {
                        try await viewModel.clearTrashBin()
                        showOverdueSheet = false
                    } catch {
                        await viewModel.loadTasks(silent: true, force: true)
                    }
                }
            }
        )
        .environment(\.locale, appSettings.appLocale)
        .environment(\.layoutDirection, appSettings.layoutDirection)
        .presentationDetents([.medium, .large])
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
        .duoReadableContentWidth()
    }

    private func editFlexibleSheet(task: FamilyTask) -> some View {
        EditTaskView(
            task: task,
            familyProfiles: viewModel.familyProfiles,
            onUpdateSuccess: { _ in
                Task {
                    await viewModel.loadTasks(silent: true, force: true)
                    await scheduleViewModel.loadTasks(silent: true)
                }
            },
            onAlarmSync: { updated in
                scheduleViewModel.syncAlarms(for: updated)
            }
        )
        .environmentObject(appRouter)
        .environment(\.locale, appSettings.appLocale)
        .environment(\.layoutDirection, appSettings.layoutDirection)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .duoReadableContentWidth()
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

        taskForEditSheet = task
        appRouter.consumePendingTaskReminderTap()
    }

    private func beginCompleteFlexibleTask(_ task: FamilyTask, playsListExitAnimation: Bool = true) {
        guard completionInFlightTaskIDs.contains(task.id) == false else { return }

        completionInFlightTaskIDs.insert(task.id)

        if playsListExitAnimation == false {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                viewModel.applyOptimisticCompletion(for: task)
            }
            Task { @MainActor in
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
            return
        }

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
                                    hasAttachments: viewModel.taskHasAttachments(task),
                                    isCompletionChecked: completionCheckedTaskIDs.contains(task.id),
                                    onToggleComplete: {
                                        beginCompleteFlexibleTask(task)
                                    },
                                    onOpen: {
                                        taskForEditSheet = task
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
        .scrollBounceBehavior(.always)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            todoSummaryFooterInset
        }
        .refreshable {
            await refreshTodos()
        }
    }

    private var todoStickyBoardScrollView: some View {
        TodoStickyBoardView(
            nearTasks: viewModel.stickyBoardNearTasks(),
            farTasks: viewModel.stickyBoardFarTasks(),
            overdueCount: viewModel.trashBinCount,
            completedCount: viewModel.completedTasks.count,
            displayTitle: { viewModel.displayTitle(for: $0) },
            forWhomAvatars: { viewModel.forWhomAvatarSources(for: $0) },
            detailLines: { stickyDetailLines(for: $0) },
            hasAttachments: { viewModel.taskHasAttachments($0) },
            isCompletionChecked: { completionCheckedTaskIDs.contains($0) },
            isFlying: { completionFlyingTaskIDs.contains($0) },
            isInteractionLocked: { completionInFlightTaskIDs.contains($0) },
            onToggleComplete: { beginCompleteFlexibleTask($0) },
            onOpen: { taskForEditSheet = $0 },
            onOpenOverdueBin: { showOverdueSheet = true },
            onOpenCompletedArchive: { showCompletedSheet = true },
            onDropComplete: { beginCompleteFlexibleTask($0, playsListExitAnimation: false) },
            onDropDelete: { task in
                Task { await beginDeleteFlexibleTask(task) }
            }
        )
        .refreshable {
            await refreshTodos()
        }
    }

    @MainActor
    private func beginDeleteFlexibleTask(_ task: FamilyTask) async {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            viewModel.applyOptimisticDeletion(for: task)
        }
        do {
            // 软删除为 cancelled，进入垃圾桶列表（过期 + 已删除）。
            try await viewModel.deleteFlexibleTask(
                task,
                actingMembershipId: appRouter.selectedMembershipId
            )
            await scheduleViewModel.loadTasks(silent: true)
        } catch {
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
        .scrollBounceBehavior(.always)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            todoSummaryFooterInset
        }
        .refreshable {
            await refreshTodos()
        }
    }

    private func pullToRefreshScrollContainer<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.always)
            .refreshable {
                await refreshTodos()
            }
        }
    }

    private func refreshTodos() async {
        await viewModel.loadTasks(silent: true, force: true)
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
        if appRouter.needsWriteTargetSelection {
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

    /// 便签次要信息：截止日 → 地点 → 备注，至多 2 条（与标题合计 ≤ 3）。
    private func stickyDetailLines(for task: FamilyTask) -> [String] {
        var lines: [String] = []
        if let deadline = deadlineLabel(for: task) {
            lines.append(deadline)
        }
        if let location = stickyLocationLine(for: task) {
            lines.append(location)
        }
        if let note = stickyNoteLine(for: task) {
            lines.append(note)
        }
        return Array(lines.prefix(2))
    }

    private func stickyLocationLine(for task: FamilyTask) -> String? {
        let name = task.locationData?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, name.isEmpty == false {
            return name
        }
        let address = task.locationData?.address?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let address, address.isEmpty == false {
            return address
        }
        return nil
    }

    private func stickyNoteLine(for task: FamilyTask) -> String? {
        let raw = task.description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, raw.isEmpty == false else { return nil }
        if let firstLine = raw.split(whereSeparator: \.isNewline).first {
            let line = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }
        return raw
    }
}

// MARK: - Completed sheet

private struct CompletedTasksListView: View {
    @Environment(\.dismiss) private var dismiss

    let tasks: [FamilyTask]
    let displayTitle: (FamilyTask) -> String
    let forWhomAvatars: (FamilyTask) -> [TaskCardAvatarSource]
    var taskHasAttachments: (FamilyTask) -> Bool = { $0.hasAttachmentURLs }
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
                                    style: .completed,
                                    hasAttachments: taskHasAttachments(task)
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
    var taskHasAttachments: (FamilyTask) -> Bool = { $0.hasAttachmentURLs }
    let deadlineLabel: (FamilyTask) -> String?
    let onSelectTask: (FamilyTask) -> Void
    var onClearTrash: (() -> Void)? = nil

    @State private var showClearConfirm = false

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
                            style: .overdue,
                            hasAttachments: taskHasAttachments(task)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Todo.clear) {
                        showClearConfirm = true
                    }
                    .disabled(tasks.isEmpty || onClearTrash == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                }
            }
            .alert(
                L10n.Todo.clearTrashConfirmTitle,
                isPresented: $showClearConfirm
            ) {
                Button(L10n.Todo.clear, role: .destructive) {
                    onClearTrash?()
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                Text(L10n.Todo.clearTrashConfirmMessage.localized)
            }
        }
    }
}

// MARK: - Display mode

private enum TodoDisplayMode: String {
    case list
    case sticky
}

// MARK: - Row

private struct TodoFlexibleRow: View {
    enum Style {
        case active
        case overdue
        case completed
    }

    @Environment(\.colorScheme) private var colorScheme

    let task: FamilyTask
    let displayTitle: String
    let forWhomAvatars: [TaskCardAvatarSource]
    let deadlineLabel: String?
    let style: Style
    var hasAttachments: Bool = false
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
                TaskCardForWhomTrailing(
                    sources: forWhomAvatars,
                    style: .compact,
                    showsEmptyPlaceholder: false,
                    accentColor: task.cardThemeAccentColor
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .padding(.bottom, hasAttachments ? 12 : 0)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(task.cardHeaderAccentColor)
                .frame(width: 4)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            if hasAttachments {
                Image(systemName: "paperclip")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.taskCardSecondary(for: colorScheme))
                    .padding(.trailing, 10)
                    .padding(.bottom, 6)
                    .accessibilityLabel(L10n.Common.attachments.localized)
            }
        }
    }

    private var rowBackground: Color {
        let surface = Color.taskCardSurface(for: colorScheme)
        return style == .completed ? surface.opacity(0.72) : surface
    }

    @ViewBuilder
    private var leadingControl: some View {
        if style == .active, let onToggleComplete {
            Button(action: onToggleComplete) {
                Image(systemName: isCompletionChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompletionChecked ? .green : task.cardThemeAccentColor)
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
            return Color.green.opacity(0.55)
        case .active, .overdue:
            return Color.taskCardStroke(for: colorScheme)
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
            return task.cardThemeAccentColor
        }
    }

    private var titleColor: Color {
        Color.taskCardTitle(for: colorScheme)
    }

    private var subtitleColor: Color {
        switch style {
        case .overdue:
            return .red.opacity(0.9)
        case .completed, .active:
            return Color.taskCardSecondary(for: colorScheme)
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
