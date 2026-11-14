import SwiftUI
import UIKit

#if canImport(Supabase)
import Supabase
#endif

private struct CreateTaskSheetRequest: Identifiable {
    let id = UUID()
    let prefillTitle: String
    let defaultDueDate: Date?
}

/// 任务 / 日程主页：顶栏日历风格导航 + 多视图模式路由。
struct TaskListView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @StateObject private var viewModel = AppViewModels.makeScheduleViewModel()

    @AppStorage("schedule_calendar_view_mode") private var scheduleViewModeRaw = CalendarViewMode.day.rawValue
    @AppStorage("schedule_year_drill_down_view_mode") private var yearDrillDownViewModeRaw = CalendarViewMode.day.rawValue
    @State private var selectedDate: Date = Date()

    /// 日程展示样式（List / Day / Week / Month / Year），跨启动持久化。
    private var currentViewMode: CalendarViewMode {
        Self.resolvedScheduleMode(from: scheduleViewModeRaw)
    }

    /// 从年视图钻取时恢复到的微观视图（日 / 周 / 月等）。
    private var yearDrillDownViewMode: CalendarViewMode {
        Self.resolvedScheduleMode(from: yearDrillDownViewModeRaw)
    }

    private func setCurrentViewMode(_ mode: CalendarViewMode) {
        scheduleViewModeRaw = mode.rawValue
    }

    private func setYearDrillDownViewMode(_ mode: CalendarViewMode) {
        yearDrillDownViewModeRaw = mode.rawValue
    }

    @State private var isShowingCalendarSheet = false
    /// 用 `sheet(item:)` 携带预填标题，避免 `isPresented` 首次弹出时读到旧 state。
    @State private var createTaskSheetRequest: CreateTaskSheetRequest?
    @State private var pendingCreateAfterWritePick: CreateTaskSheetRequest?
    @State private var isShowingWriteTargetPicker = false
    @State private var isShowingSearch = false
    @State private var taskForDetailSheet: FamilyTask?
    @State private var taskPendingDelete: FamilyTask?
    /// 与 `taskPendingDelete` 分离：alert 关闭时会先把 isPresented 置 false，若用 pending!=nil 绑定会清掉任务再跑按钮。
    @State private var isShowingContextMenuDeleteAlert = false
    @State private var listScrollToken = 0
    @State private var aiPrefillFormInstanceID = UUID()
    /// 周视图「回到本周」：由 `TaskWeekGridView` 同步可见性；递增 trigger 触发跳转。
    @State private var showsWeekBackToCurrentWeekButton = false
    @State private var weekBackToCurrentWeekTrigger = 0
    /// 月视图「回到本月」。
    @State private var showsMonthBackToCurrentMonthButton = false
    @State private var monthBackToCurrentMonthTrigger = 0
    @State private var isShowingInviteSheet = false
    @State private var isShowingScheduleBackgroundSettings = false

    var body: some View {
        // 日程是全幅画布（日/周/月）；Duo / iPad 宽屏也不做列表+详情分栏，
        // 否则半屏会落成空的「Select」占位，周视图被挤到一侧。
        NavigationStack {
            ZStack {
                mainContent
                if viewModel.isAIProcessing {
                    aiProcessingOverlay
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomAccessoryBar
            }
            .schedulePageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { scheduleToolbar }
            .sheet(isPresented: $isShowingScheduleBackgroundSettings) {
                ScheduleBackgroundSettingsSheet()
                    .environmentObject(appSettings)
            }
            .modifier(
                ScheduleEditSheetModifier(
                    task: $taskForDetailSheet,
                    viewModel: viewModel,
                    appRouter: appRouter,
                    appSettings: appSettings
                )
            )
            .sheet(item: $createTaskSheetRequest) { request in
                EditTaskView(
                    formMode: .scheduled,
                    initialTitle: request.prefillTitle,
                    defaultDueDate: request.defaultDueDate ?? dayID(for: selectedDate),
                    defaultAllDayForNewTask: false,
                    onSaveSuccess: { createdDueDate in
                        selectedDate = dayID(for: createdDueDate)
                        Task {
                            await viewModel.loadTasks()
                        }
                    },
                    onAlarmSync: { task in
                        viewModel.syncAlarms(for: task)
                    }
                )
                .environmentObject(appRouter)
                .presentationDetents([.large])
                .duoReadableContentWidth()
            }
            .sheet(isPresented: $isShowingInviteSheet) {
                InviteMemberView(
                    currentHouseholdId: appRouter.selectedHouseholdId,
                    creatorMembershipId: appRouter.selectedMembershipId,
                    activeMemberCount: viewModel.householdMembers.filter { $0.isActiveMembership() }.count,
                    hasPremiumAccess: appRouter.hasPremiumAccess
                )
                .environmentObject(appRouter)
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingWriteTargetPicker) {
                WriteTargetHouseholdPicker { _ in
                    let pending = pendingCreateAfterWritePick
                    pendingCreateAfterWritePick = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        createTaskSheetRequest = pending
                    }
                }
                .environmentObject(appRouter)
                .presentationDetents([.medium])
            }
            .onAppear {
                applyScheduleWidgetRoute()
            }
            .onChange(of: appRouter.pendingScheduleWidgetRoute) { _, _ in
                applyScheduleWidgetRoute()
            }
            .onChange(of: appRouter.appState) { _, _ in
                applyScheduleWidgetRoute()
            }
            .onChange(of: isShowingWriteTargetPicker) { _, isPresented in
                if isPresented == false, createTaskSheetRequest == nil {
                    // 用户取消选择组织时丢弃 pending，避免误开创建页。
                    pendingCreateAfterWritePick = nil
                }
            }
            .sheet(isPresented: $isShowingSearch) {
                ScheduleSearchView(
                    onOpenTask: { _ in },
                    onOpenLedger: { _ in
                        // 账本详情在 Wallet Tab；搜索结果先切到主组织上下文即可。
                    },
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
            .sheet(item: $viewModel.prefilledTaskForAI) { draft in
                EditTaskView(
                    formMode: draft.prefersFlexibleTask ? .flexible : .scheduled,
                    initialTitle: draft.title,
                    initialNote: draft.description,
                    initialLocationName: draft.locationName,
                    initialDueDate: draft.dueDate,
                    initialEndDatetime: draft.endDatetime,
                    initialIsAllDay: draft.isAllDay,
                    initialDurationMinutes: draft.durationMinutes,
                    initialCostDisplay: draft.costDisplay,
                    initialAssigneeMembershipIds: draft.assigneeMembershipIds,
                    initialTargetProfileIds: draft.targetProfileIds,
                    initialPriorityUrgent: draft.isPriorityUrgent,
                    initialAttachmentImages: [draft.attachmentImage],
                    initialAttachmentJPEGData: [draft.attachmentJPEGData],
                    defaultDueDate: draft.dueDate.map { dayID(for: $0) } ?? dayID(for: selectedDate),
                    defaultAllDayForNewTask: draft.isAllDay,
                    onSaveSuccess: { createdDueDate in
                        selectedDate = dayID(for: createdDueDate)
                        Task {
                            await viewModel.loadTasks()
                        }
                    },
                    onAlarmSync: { task in
                        viewModel.syncAlarms(for: task)
                    }
                )
                .id(aiPrefillFormInstanceID)
                .environmentObject(appRouter)
                .presentationDetents([.large])
            }
            .fullScreenCover(isPresented: $viewModel.isShowingCamera) {
                CameraPicker(
                    onImageCaptured: { source, originalImage, _ in
                        viewModel.isShowingCamera = false
                        viewModel.presentCrop(for: originalImage, source: source)
                    },
                    onCancel: {
                        viewModel.isShowingCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $viewModel.pendingCropContext) { context in
                AIPhotoCropSheet(
                    image: context.image,
                    onConfirm: { normalizedQuad in
                        guard PremiumLimits.canUseAIPhotoTaskCreation(
                            hasPremium: appRouter.hasPremiumAccess
                        ) else {
                            appRouter.presentPremiumUpgrade()
                            return
                        }
                        viewModel.confirmCrop(
                            normalizedQuad: normalizedQuad,
                            image: context.image,
                            source: context.source,
                            targetDate: dayID(for: selectedDate),
                            hasPremiumAccess: appRouter.hasPremiumAccess,
                            usePremiumQuality: appRouter.hasPremiumAccess
                        )
                    },
                    onRetake: {
                        viewModel.cancelCrop()
                        viewModel.isShowingCamera = true
                    }
                )
                .ignoresSafeArea()
            }
            .alert(L10n.Common.imageRecognitionFailed, isPresented: aiErrorAlertBinding) {
                Button(L10n.Common.ok, role: .cancel) {
                    viewModel.aiProcessingError = nil
                }
            } message: {
                if let message = viewModel.aiProcessingError {
                    Text(message)
                }
            }
            .alert(
                L10n.Common.notice,
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if $0 == false { viewModel.clearErrorMessage() } }
                )
            ) {
                Button(L10n.Common.ok, role: .cancel) {
                    viewModel.clearErrorMessage()
                }
            } message: {
                if let message = viewModel.errorMessage {
                    Text(message)
                }
            }
            .alert(
                L10n.Schedule.deleteTask,
                isPresented: $isShowingContextMenuDeleteAlert
            ) {
                if taskPendingDelete?.seriesGrouping != nil {
                    Button(L10n.Schedule.deleteThisTaskOnly, role: .destructive) {
                        Task { await performContextMenuDelete(scope: .singleOnly) }
                    }
                    Button(L10n.Schedule.deleteThisTaskAndLater, role: .destructive) {
                        Task { await performContextMenuDelete(scope: .thisAndFuture) }
                    }
                } else {
                    Button(L10n.Schedule.deleteThisTaskOnly, role: .destructive) {
                        Task { await performContextMenuDelete(scope: .singleOnly) }
                    }
                }
                Button(L10n.Common.cancel, role: .cancel) {
                    taskPendingDelete = nil
                }
            } message: {
                if taskPendingDelete?.seriesGrouping == nil {
                    Text(L10n.Common.thisActionCannotBeUndone2.localized)
                } else {
                    Text(L10n.Common.pleaseSelectAScopeToDelete.localized)
                }
            }
            .task(id: taskLoadTrigger) {
                viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
                viewModel.setViewHouseholdIds(appRouter.selectedHouseholdIds)
                guard appRouter.hasCompletedAuthBootstrap else { return }
                await viewModel.loadTasks()
                openPendingScheduledTaskIfNeeded()
                await viewModel.setupRealtimeListener()
            }
            .onDisappear {
                Task {
                    await viewModel.stopRealtimeListener()
                }
            }
            .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
                viewModel.setHouseholdContext(newValue)
                Task {
                    guard appRouter.hasCompletedAuthBootstrap else { return }
                    await viewModel.setupRealtimeListener()
                }
            }
            .onChange(of: appRouter.viewHouseholdIdsToken) { _, _ in
                viewModel.setViewHouseholdIds(appRouter.selectedHouseholdIds)
                Task {
                    guard appRouter.hasCompletedAuthBootstrap else { return }
                    await viewModel.loadTasks()
                    openPendingScheduledTaskIfNeeded()
                }
            }
            .onChange(of: scheduleViewModeRaw) { oldRaw, newRaw in
                let oldMode = Self.resolvedScheduleMode(from: oldRaw)
                let mode = Self.resolvedScheduleMode(from: newRaw)
                if mode == .week {
                    WeekViewPerformanceTracer.beginTrace(
                        entryPath: "modeSwitch.\(oldMode.rawValue)->\(mode.rawValue)",
                        scheduledTaskCount: viewModel.scheduledTasks.count,
                        totalTaskCount: viewModel.tasks.count
                    )
                } else if oldMode == .week {
                    WeekViewPerformanceTracer.cancelTrace(reason: "leftWeekMode->\(mode.rawValue)")
                }
                if mode == .list {
                    let today = dayID(for: Date())
                    selectedDate = today
                    viewModel.noteVisibleMonth(containing: today)
                    listScrollToken += 1
                }
                if mode == .year {
                    let year = Calendar.current.component(.year, from: selectedDate)
                    viewModel.setYearViewYear(year, locale: locale)
                }
                if mode != .year, mode != .list {
                    setYearDrillDownViewMode(mode)
                }
            }
            .onChange(of: selectedDate) { _, newValue in
                let normalized = dayID(for: newValue)
                if selectedDate != normalized {
                    selectedDate = normalized
                }
                // 日/周侧滑仅本地按日过滤，勿在此 loadTasks（会清空列表并打网，易卡死）。
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleTasksDidChange)) { _ in
                Task {
                    await viewModel.loadTasks(silent: true)
                }
            }
            .onChange(of: viewModel.prefilledTaskForAI?.id) { _, _ in
                aiPrefillFormInstanceID = UUID()
            }
            .onChange(of: appRouter.pendingTaskReminderTap) { _, _ in
                openPendingScheduledTaskIfNeeded()
            }
            .onChange(of: viewModel.tasks) { _, _ in
                openPendingScheduledTaskIfNeeded()
            }
        }
        .appLocaleEnvironment(using: appSettings)
    }

    private var mainContent: some View {
        ZStack {
            scheduleModeContent
            if viewModel.shouldBlockSchedulePresentation {
                ScheduleInitialLoadingView(locale: locale)
            }
        }
    }

    private var scheduleModeContent: some View {
        VStack(spacing: 0) {
            Group {
                switch currentViewMode {
                case .list:
                    TaskModeListView(
                        viewModel: viewModel,
                        listScrollToken: listScrollToken,
                        scrollAnchorDate: selectedDate,
                        onTaskTap: { taskForDetailSheet = $0 },
                        onTaskComplete: { completeTaskFromContextMenu($0) },
                        onTaskDelete: { requestDeleteFromContextMenu($0) },
                        onRefresh: refreshTasks
                    )
                case .day:
                    TaskModeDayView(
                        selectedDate: $selectedDate,
                        viewModel: viewModel,
                        onTaskSelect: { taskForDetailSheet = $0 },
                        onTaskComplete: { completeTaskFromContextMenu($0) },
                        onTaskDelete: { requestDeleteFromContextMenu($0) },
                        onRefresh: refreshTasks
                    )
                case .week:
                    TaskWeekGridView(
                        selectedDate: $selectedDate,
                        viewModel: viewModel,
                        onTaskSelect: { taskForDetailSheet = $0 },
                        onTaskComplete: { completeTaskFromContextMenu($0) },
                        onTaskDelete: { requestDeleteFromContextMenu($0) },
                        onRefresh: refreshTasks,
                        showsBackToCurrentWeekButton: $showsWeekBackToCurrentWeekButton,
                        backToCurrentWeekTrigger: $weekBackToCurrentWeekTrigger
                    )
                case .year:
                    TaskYearView(
                        viewModel: viewModel,
                        selectedDate: $selectedDate,
                        onMonthSelected: { monthStart in
                            drillDownFromYear(to: monthStart)
                        },
                        onDateSelected: { date in
                            drillDownFromYear(to: date)
                        }
                    )
                case .month:
                    TaskMonthView(
                        selectedDate: $selectedDate,
                        tasks: viewModel.scheduledTasks,
                        titleForTask: { viewModel.displayTitle(for: $0) },
                        onSelectDay: { date in
                            selectedDate = dayID(for: date)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                setCurrentViewMode(.day)
                            }
                        },
                        onSelectTask: { taskForDetailSheet = $0 },
                        onTaskComplete: { completeTaskFromContextMenu($0) },
                        onTaskDelete: { requestDeleteFromContextMenu($0) },
                        showsBackToCurrentMonthButton: $showsMonthBackToCurrentMonthButton,
                        backToCurrentMonthTrigger: $monthBackToCurrentMonthTrigger
                    )
                case .threeDay:
                    Text(AppLocalized.string(L10n.Common.underDevelopment, locale: locale))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 底部：左侧月份入口（及周视图「回到本周」）+ 右侧创建 FAB。
    private var bottomAccessoryBar: some View {
        HStack(spacing: 12) {
            if showsBottomMonthPicker {
                ScheduleMonthYearPickerButton(title: navigationMonthYearTitle) {
                    isShowingCalendarSheet = true
                }
                .sheet(isPresented: $isShowingCalendarSheet) {
                    CalendarSheetView(
                        selectedDate: $selectedDate,
                        monthTaskDots: monthTaskDots
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }

            bottomLeadingAccessory

            Spacer(minLength: 8)
                .allowsHitTesting(false)

            createTaskFAB
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var bottomLeadingAccessory: some View {
        if currentViewMode == .week, showsWeekBackToCurrentWeekButton {
            Button {
                weekBackToCurrentWeekTrigger += 1
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(AppTheme.ColorToken.accent, in: Circle())
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Common.today)
        } else if currentViewMode == .month, showsMonthBackToCurrentMonthButton {
            Button {
                monthBackToCurrentMonthTrigger += 1
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(AppTheme.ColorToken.accent, in: Circle())
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Common.today)
        }
    }

    private var showsBottomMonthPicker: Bool {
        switch currentViewMode {
        case .year:
            return false
        case .day, .week, .list, .month, .threeDay:
            return true
        }
    }

    private var aiProcessingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text(L10n.Common.aiIsReadingYourImage.localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isAIProcessing)
    }

    private var aiErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.aiProcessingError != nil },
            set: { isPresented in
                if isPresented == false {
                    viewModel.aiProcessingError = nil
                }
            }
        )
    }

    /// household 或 auth bootstrap 完成后触发任务加载，避免 JWT 刷新前过早请求。
    private var taskLoadTrigger: String {
        "\(appRouter.viewHouseholdIdsToken)-\(appRouter.hasCompletedAuthBootstrap)"
    }

    // MARK: - Notification deep link

    @MainActor
    private func openPendingScheduledTaskIfNeeded() {
        guard let pending = appRouter.pendingTaskReminderTap else { return }
        guard pending.isFlexibleTodo == false else { return }
        guard appRouter.selectedHouseholdId == pending.householdId else { return }
        guard let task = viewModel.scheduledTasks.first(where: { $0.id == pending.taskId }) else {
            // 组织已匹配且任务列表已更新，但目标任务不存在：留在组织主页，清空深链状态。
            appRouter.consumePendingTaskReminderTap()
            return
        }

        taskForDetailSheet = task
        appRouter.consumePendingTaskReminderTap()
    }

    // MARK: - Top bar（参考 Apple Calendar）

    @ToolbarContentBuilder
    private var scheduleToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            GroupSwitcherToolbarButton()
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                FamilyPrintToolbarButton { delivery in
                    printSchedule(delivery: delivery)
                }
                Button {
                    isShowingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel(L10n.Schedule.search)
                scheduleOptionsMenu
            }
        }
    }

    private var createTaskFAB: some View {
        Button {
            openCreateTask(prefill: "")
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(AppTheme.ColorToken.accent, in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Schedule.createNewTask)
    }

    private var scheduleOptionsMenu: some View {
        Menu {
            Section {
                ForEach(CalendarViewMode.menuCases, id: \.self) { mode in
                    Button {
                        setCurrentViewMode(mode)
                    } label: {
                        HStack {
                            Text(mode.menuTitleKey)
                            Spacer(minLength: 8)
                            if mode == currentViewMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    Task { @MainActor in
                        // Menu 收起后再呈 Sheet，避免同帧冲突导致不弹出。
                        try? await Task.sleep(for: .milliseconds(80))
                        isShowingScheduleBackgroundSettings = true
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

    private func printSchedule(delivery: FamilyPrintDelivery) {
        let calendar = appSettings.effectiveCalendar
        let jobName = "\(GroupSwitcherData.currentName(for: appRouter)) · \(schedulePrintRangeTitle(calendar: calendar))"
        let context = SchedulePrintContext(
            jobName: jobName,
            householdName: GroupSwitcherData.currentName(for: appRouter),
            tasks: viewModel.scheduledTasks,
            calendar: calendar,
            locale: locale,
            selectedDate: selectedDate,
            displayTitle: { viewModel.displayTitle(for: $0) },
            avatars: { viewModel.forWhomAvatarSources(for: $0) },
            assigneeLabel: { viewModel.assigneeLabel(for: $0, locale: locale) },
            hasAttachments: { viewModel.taskHasAttachments($0) },
            delivery: delivery
        )
        switch currentViewMode {
        case .week:
            SchedulePrintComposer.printWeek(context)
        case .month:
            SchedulePrintComposer.printMonth(context)
        case .year:
            viewModel.refreshYearViewSnapshot(locale: locale)
            SchedulePrintComposer.printYear(context, snapshot: viewModel.yearCalendarSnapshot)
        case .list:
            SchedulePrintComposer.printList(context)
        case .day, .threeDay:
            SchedulePrintComposer.printDay(context)
        }
    }

    private func schedulePrintInterval(calendar: Calendar) -> DateInterval? {
        switch currentViewMode {
        case .list:
            return nil
        case .year:
            return calendar.dateInterval(of: .year, for: navigationReferenceDate)
        case .month:
            return calendar.dateInterval(of: .month, for: selectedDate)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: selectedDate)
        case .threeDay:
            let start = calendar.startOfDay(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 3, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .day:
            let start = calendar.startOfDay(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
    }

    private func schedulePrintRangeTitle(calendar: Calendar) -> String {
        switch currentViewMode {
        case .list:
            return L10n.Common.list.string(locale: locale)
        case .year:
            return navigationReferenceDate.formatted(.dateTime.year().locale(locale))
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year().locale(locale))
        case .day:
            return selectedDate.formatted(
                .dateTime.weekday(.wide).month(.abbreviated).day().locale(locale)
            )
        case .week:
            let days = ScheduleWeekCalendar.daysInWeek(
                weekStart: ScheduleWeekCalendar.startOfWeek(for: selectedDate, calendar: calendar),
                calendar: calendar
            )
            let start = (days.first ?? selectedDate).formatted(
                .dateTime.month(.abbreviated).day().locale(locale)
            )
            let end = (days.last ?? selectedDate).formatted(
                .dateTime.month(.abbreviated).day().locale(locale)
            )
            return "\(start) – \(end)"
        case .threeDay:
            guard let interval = schedulePrintInterval(calendar: calendar) else { return "" }
            let start = interval.start.formatted(.dateTime.month(.abbreviated).day().locale(locale))
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
            let end = last.formatted(.dateTime.month(.abbreviated).day().locale(locale))
            return "\(start) – \(end)"
        }
    }

    private var navigationReferenceDate: Date {
        switch currentViewMode {
        case .list:
            return viewModel.currentVisibleDate
        case .year:
            var components = DateComponents()
            components.year = viewModel.yearViewSelectedYear
            components.month = 1
            components.day = 1
            return Calendar.current.date(from: components) ?? selectedDate
        default:
            return selectedDate
        }
    }

    private var navigationMonthYearTitle: String {
        navigationReferenceDate.formatted(
            .dateTime
                .month(.abbreviated)
                .year()
                .locale(locale)
        )
    }

    private func applyScheduleWidgetRoute() {
        guard let route = appRouter.pendingScheduleWidgetRoute else { return }
        guard appRouter.appState == .activeMember else { return }
        appRouter.pendingScheduleWidgetRoute = nil
        switch route {
        case .openDay(let year, let month, let day):
            selectedDate = date(year: year, month: month, day: day)
            setCurrentViewMode(.day)
        case .createTask(let year, let month, let day):
            let due = date(year: year, month: month, day: day)
            selectedDate = due
            setCurrentViewMode(.day)
            openCreateTask(prefill: "", defaultDueDateOverride: due)
        }
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = appSettings.effectiveTimeZone
        return appSettings.effectiveCalendar.date(from: components) ?? dayID(for: Date())
    }

    private func openCreateTask(prefill: String, defaultDueDateOverride: Date? = nil) {
        let request = CreateTaskSheetRequest(
            prefillTitle: prefill,
            defaultDueDate: defaultDueDateOverride
        )
        createTaskSheetRequest = request
    }

    private func dayID(for date: Date) -> Date {
        appSettings.effectiveCalendar.startOfDay(for: date)
    }

    private static func resolvedScheduleMode(from raw: String) -> CalendarViewMode {
        let mode = CalendarViewMode(rawValue: raw) ?? .day
        switch mode {
        case .threeDay:
            return .day
        case .list, .day, .week, .month, .year:
            return mode
        }
    }

    private func drillDownFromYear(to date: Date) {
        let normalized = dayID(for: date)
        selectedDate = normalized
        withAnimation(.easeInOut(duration: 0.25)) {
            setCurrentViewMode(yearDrillDownViewMode)
        }
    }

    private var monthTaskDots: [Date: [Color]] {
        var result: [Date: [Color]] = [:]
        for task in viewModel.scheduledTasks {
            let day = task.scheduleDisplayDay(displayCalendar: appSettings.effectiveCalendar)
            let color = statusColor(for: task.status)
            var colors = result[day, default: []]
            if colors.contains(where: { $0.description == color.description }) == false {
                colors.append(color)
            }
            result[day] = colors
        }
        return result
    }

    private func taskDisplayDate(_ task: FamilyTask) -> Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private func statusColor(for status: TaskStatus) -> Color {
        switch status {
        case .new:
            return .blue
        case .accepted, .inProgress:
            return .orange
        case .completed:
            return .green
        case .issue, .expired, .failed, .cancelled:
            return .red
        }
    }

    @MainActor
    private func refreshTasks() async {
        await LocalFirstSyncCoordinator.syncNow(reason: "pullToRefreshSchedule")
        await viewModel.loadTasks(silent: true)
    }

    private func completeTaskFromContextMenu(_ task: FamilyTask) {
        Task { @MainActor in
            let completionLocation: TaskCompletionLocation?
            if let membershipId = appRouter.selectedMembershipId {
                completionLocation = await TaskCompletionLocationProvider.currentSnapshot(
                    completedBy: membershipId
                )
            } else {
                completionLocation = nil
            }
            do {
                _ = try await viewModel.patchTaskStatus(
                    taskId: task.id,
                    to: .completed,
                    completionLocation: completionLocation,
                    actingMembershipId: appRouter.selectedMembershipId
                )
                AnalyticsManager.logTaskCompleted(
                    taskId: task.id,
                    householdId: task.householdId,
                    taskType: AnalyticsManager.analyticsTaskType(for: task)
                )
                ReviewRedirectManager.shared.checkAndTriggerAlert(for: .firstCompletion)
                NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            } catch {
                // `viewModel.errorMessage` 已由 patch 写入，顶层 notice alert 会展示。
            }
        }
    }

    private func requestDeleteFromContextMenu(_ task: FamilyTask) {
        let role = TaskEditAccess.role(
            of: appRouter.selectedMembershipId,
            in: viewModel.householdMembers
        )
        let canEdit = TaskEditAccess.canEdit(
            task,
            membershipId: appRouter.selectedMembershipId,
            role: role
        )
        TaskDeleteLogger.step(
            .tapDelete,
            source: .contextMenu,
            taskId: task.id,
            householdId: task.householdId,
            membershipId: appRouter.selectedMembershipId,
            isCreator: appRouter.selectedMembershipId == task.creatorId,
            allowsEditing: canEdit,
            detail: "role=\(role?.rawValue ?? "nil") status=\(task.status.rawValue)"
        )
        guard canEdit else {
            TaskDeleteLogger.step(
                .permissionBlocked,
                source: .contextMenu,
                taskId: task.id,
                householdId: task.householdId,
                membershipId: appRouter.selectedMembershipId,
                isCreator: appRouter.selectedMembershipId == task.creatorId,
                allowsEditing: false,
                detail: "TaskEditAccess.canEdit=false"
            )
            viewModel.presentErrorMessage(
                AppLocalized.string(L10n.Common.youDonTHavePermissionToPerformThisAction, locale: locale)
            )
            return
        }
        taskPendingDelete = task
        isShowingContextMenuDeleteAlert = true
        TaskDeleteLogger.step(
            .confirmPresented,
            source: .contextMenu,
            taskId: task.id,
            householdId: task.householdId,
            detail: "series=\(task.seriesGrouping != nil)"
        )
    }

    @MainActor
    private func performContextMenuDelete(scope: ScheduleContextMenuDeleteScope) async {
        guard let task = taskPendingDelete else {
            TaskDeleteLogger.step(.failed, source: .contextMenu, detail: "taskPendingDelete_nil")
            return
        }
        let scopeLabel = scope == .singleOnly ? "single_only" : "this_and_future"
        TaskDeleteLogger.step(
            .confirmAccepted,
            source: .contextMenu,
            taskId: task.id,
            householdId: task.householdId,
            scope: scopeLabel,
            membershipId: appRouter.selectedMembershipId,
            isCreator: appRouter.selectedMembershipId == task.creatorId
        )
        taskPendingDelete = nil
        #if canImport(Supabase)
        do {
            switch scope {
            case .singleOnly:
                try await viewModel.deleteTask(taskId: task.id)
                NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            case .thisAndFuture:
                guard let grouping = task.seriesGrouping else {
                    try await viewModel.deleteTask(taskId: task.id)
                    NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
                    return
                }
                let cutoff = task.dueDate ?? .distantPast
                let rows = try await TaskSeriesSupabaseSupport.fetchSeriesTasks(
                    householdId: task.householdId,
                    grouping: grouping,
                    dueOnOrAfter: cutoff
                )
                let ids = rows.map(\.id)
                TaskDeleteLogger.step(
                    .remoteReturned,
                    source: .contextMenu,
                    taskId: task.id,
                    householdId: task.householdId,
                    scope: scopeLabel,
                    detail: "series_count=\(ids.count)"
                )
                for id in ids {
                    await NotificationManager.shared.cancelAllPending(for: id)
                }
                try await TaskSeriesSupabaseSupport.deleteTasks(ids: ids)
                await viewModel.loadTasks()
                NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            }
            TaskDeleteLogger.succeeded(
                source: .contextMenu,
                taskId: task.id,
                householdId: task.householdId,
                scope: scopeLabel
            )
        } catch {
            TaskDeleteLogger.failure(
                step: .failed,
                error: error,
                source: .contextMenu,
                taskId: task.id,
                householdId: task.householdId,
                scope: scopeLabel
            )
            viewModel.presentErrorMessage(
                String(
                    format: L10n.Common.deleteFailed.string(locale: locale),
                    error.localizedDescription
                )
            )
        }
        #else
        _ = scope
        do {
            try await viewModel.deleteTask(taskId: task.id)
        } catch {
            TaskDeleteLogger.failure(
                step: .failed,
                error: error,
                source: .contextMenu,
                taskId: task.id,
                householdId: task.householdId,
                scope: scopeLabel,
                detail: "sdk_unavailable_build"
            )
            viewModel.presentErrorMessage(error.localizedDescription)
        }
        #endif
    }
}

private enum ScheduleContextMenuDeleteScope {
    case singleOnly
    case thisAndFuture
}

// MARK: - Edit presentation（点击任务直接进入编辑 sheet）

private struct ScheduleEditSheetModifier: ViewModifier {
    @Binding var task: FamilyTask?
    @ObservedObject var viewModel: ScheduleViewModel
    @ObservedObject var appRouter: AppRouter
    @ObservedObject var appSettings: AppSettingsManager

    func body(content: Content) -> some View {
        content.sheet(item: $task) { presented in
            let role = TaskEditAccess.role(
                of: appRouter.selectedMembershipId,
                in: viewModel.householdMembers
            )
            let allowsEditing = TaskEditAccess.canEdit(
                presented,
                membershipId: appRouter.selectedMembershipId,
                role: role
            )
            EditTaskView(
                task: presented,
                familyProfiles: viewModel.familyProfiles,
                allowsEditing: allowsEditing,
                onUpdateSuccess: { _ in
                    Task { await viewModel.loadTasks(silent: true) }
                },
                onAlarmSync: { updated in
                    viewModel.syncAlarms(for: updated)
                }
            )
            .environmentObject(appRouter)
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
            .presentationDetents([.large])
            .duoReadableContentWidth()
        }
    }
}

#Preview {
    TaskListView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
