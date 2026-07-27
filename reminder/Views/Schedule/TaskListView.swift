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

    @State private var currentViewMode: CalendarViewMode = .day
    @State private var selectedDate: Date = Date()
    /// 从年视图钻取时恢复到的微观视图（日 / 周）。
    @State private var yearDrillDownViewMode: CalendarViewMode = .day

    @State private var isShowingCalendarSheet = false
    /// 用 `sheet(item:)` 携带预填标题，避免 `isPresented` 首次弹出时读到旧 state。
    @State private var createTaskSheetRequest: CreateTaskSheetRequest?
    @State private var pendingCreateAfterWritePick: CreateTaskSheetRequest?
    @State private var isShowingWriteTargetPicker = false
    @State private var isShowingSearch = false
    @State private var taskForDetailSheet: FamilyTask?
    @State private var currentMembershipRole: MembershipRole = .member
    @State private var listScrollToken = 0
    @State private var quickTaskInput = ""
    @State private var aiPrefillFormInstanceID = UUID()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                mainContent
                createTaskFAB
                if viewModel.isAIProcessing {
                    aiProcessingOverlay
                }
            }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { scheduleToolbar }
            .sheet(item: $taskForDetailSheet) { task in
                NavigationStack {
                    TaskDetailView(
                        initialTask: task,
                        currentUserRole: currentMembershipRole,
                        assigneeDisplayName: assigneeLabel(for: task),
                        scheduleViewModel: viewModel
                    )
                    .environmentObject(appRouter)
                }
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingCalendarSheet) {
                CalendarSheetView(
                    selectedDate: $selectedDate,
                    monthTaskDots: monthTaskDots
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
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
            .onChange(of: isShowingWriteTargetPicker) { _, isPresented in
                if isPresented == false, createTaskSheetRequest == nil {
                    // 用户取消选择组织时丢弃 pending，避免误开创建页。
                    pendingCreateAfterWritePick = nil
                }
            }
            .sheet(isPresented: $isShowingSearch) {
                ScheduleSearchView(
                    onOpenTask: { task in
                        taskForDetailSheet = task
                    },
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
            .task(id: taskLoadTrigger) {
                viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
                viewModel.setViewHouseholdIds(appRouter.selectedHouseholdIds)
                guard appRouter.hasCompletedAuthBootstrap else { return }
                await viewModel.loadTasks()
                openPendingScheduledTaskIfNeeded()
                await refreshCurrentMembershipRole()
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
                    await refreshCurrentMembershipRole()
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
            .onChange(of: appRouter.selectedMembershipId) { _, _ in
                Task {
                    await refreshCurrentMembershipRole()
                }
            }
            .onChange(of: currentViewMode) { oldMode, mode in
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
                    viewModel.noteVisibleMonth(containing: Date())
                    listScrollToken += 1
                }
                if mode == .year {
                    let year = Calendar.current.component(.year, from: selectedDate)
                    viewModel.setYearViewYear(year, locale: locale)
                }
                if mode != .year, mode != .list {
                    yearDrillDownViewMode = mode
                }
            }
            .onChange(of: selectedDate) { _, newValue in
                let normalized = dayID(for: newValue)
                if selectedDate != normalized {
                    selectedDate = normalized
                    return
                }
                Task {
                    await viewModel.loadTasks()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleTasksDidChange)) { _ in
                Task {
                    await viewModel.loadTasks()
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
        VStack(spacing: 0) {
            Group {
                switch currentViewMode {
                case .list:
                    VStack(spacing: 0) {
                        scheduleSecondRowMonthBar
                        TaskModeListView(
                            viewModel: viewModel,
                            listScrollToken: listScrollToken,
                            onTaskTap: { taskForDetailSheet = $0 },
                            onRefresh: refreshTasks
                        )
                    }
                case .day:
                    TaskModeDayView(
                        selectedDate: $selectedDate,
                        viewModel: viewModel,
                        onTaskSelect: { taskForDetailSheet = $0 },
                        onQuickCreate: { prefill, dueOverride in
                            openCreateTask(prefill: prefill, defaultDueDateOverride: dueOverride)
                        },
                        onRefresh: refreshTasks,
                        onOpenMonthPicker: {
                            isShowingCalendarSheet = true
                        }
                    )
                case .week:
                    TaskWeekGridView(
                        selectedDate: $selectedDate,
                        viewModel: viewModel,
                        onTaskSelect: { taskForDetailSheet = $0 },
                        onRefresh: refreshTasks,
                        onOpenMonthPicker: {
                            isShowingCalendarSheet = true
                        }
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
                    VStack(spacing: 0) {
                        scheduleSecondRowMonthBar
                        Text(AppLocalized.string(L10n.Common.underDevelopment, locale: locale))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .threeDay:
                    Text(AppLocalized.string(L10n.Common.underDevelopment, locale: locale))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            quickTaskInputBar
        }
    }

    /// 周 / 列表 / 月视图第二行右侧的月份入口（日视图在周条内；年视图无此入口）。
    private var scheduleSecondRowMonthBar: some View {
        HStack {
            Spacer(minLength: 0)
            ScheduleMonthYearPickerButton(title: navigationMonthYearTitle) {
                isShowingCalendarSheet = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var quickTaskInputBar: some View {
        HStack(spacing: 10) {
            TextField(AppLocalized.string(L10n.Schedule.enterTaskTitle, locale: appSettings.appLocale), text: $quickTaskInput)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(submitQuickTaskInput)

            Button(action: openAIPhotoTaskCreationFlow) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAIProcessing)
            .accessibilityLabel(L10n.Schedule.createTaskFromPhoto)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
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

    private func submitQuickTaskInput() {
        let trimmed = quickTaskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        quickTaskInput = ""
        openCreateTask(prefill: trimmed)
    }

    private func openAIPhotoTaskCreationFlow() {
        viewModel.isShowingCamera = true
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
                Button {
                    isShowingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel(L10n.Schedule.search)
                calendarViewModeMenu
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
        .padding(.trailing, 20)
        .padding(.bottom, 72)
        .accessibilityLabel(L10n.Schedule.createNewTask)
    }

    private var calendarViewModeMenu: some View {
        Menu {
            ForEach(CalendarViewMode.menuCases, id: \.self) { mode in
                Button {
                    currentViewMode = mode
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
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
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
                .month(.wide)
                .year()
                .locale(locale)
        )
    }

    private func openCreateTask(prefill: String, defaultDueDateOverride: Date? = nil) {
        let request = CreateTaskSheetRequest(
            prefillTitle: prefill,
            defaultDueDate: defaultDueDateOverride
        )
        if appRouter.selectableHouseholds.count > 1 {
            pendingCreateAfterWritePick = request
            isShowingWriteTargetPicker = true
        } else {
            createTaskSheetRequest = request
        }
    }

    private func dayID(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func drillDownFromYear(to date: Date) {
        let normalized = dayID(for: date)
        selectedDate = normalized
        withAnimation(.easeInOut(duration: 0.25)) {
            currentViewMode = yearDrillDownViewMode
        }
    }

    private var monthTaskDots: [Date: [Color]] {
        var result: [Date: [Color]] = [:]
        for task in viewModel.scheduledTasks {
            let day = Calendar.current.startOfDay(for: taskDisplayDate(task))
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

    private func assigneeLabel(for task: FamilyTask) -> String {
        viewModel.assigneeLabel(for: task, locale: locale)
    }

    #if canImport(Supabase)
    private struct MembershipRoleRow: Decodable {
        let role: MembershipRole
    }
    #endif

    @MainActor
    private func refreshTasks() async {
        await refreshCurrentMembershipRole()
        await viewModel.loadTasks()
    }

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
}

#Preview {
    TaskListView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
