import SwiftUI
import UIKit

#if canImport(Supabase)
import Supabase
#endif

/// 任务 / 日程主页：顶栏日历风格导航 + 多视图模式路由。
struct TaskListView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator
    @StateObject private var viewModel = AppViewModels.makeScheduleViewModel()

    @State private var currentViewMode: CalendarViewMode = .day
    @State private var selectedDate: Date = Date()

    @State private var isShowingCalendarSheet = false
    @State private var isShowingCreateTaskSheet = false
    @State private var createTaskFormInstanceID = UUID()
    @State private var prefillTitle = ""
    @State private var createTaskDueDateOverride: Date?
    @State private var taskForDetailSheet: FamilyTask?
    @State private var currentMembershipRole: MembershipRole = .member
    @State private var listScrollToken = 0
    @State private var quickTaskInput = ""
    @State private var aiPrefillFormInstanceID = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                mainContent
                if viewModel.isAIProcessing {
                    aiProcessingOverlay
                }
            }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationBarHidden(true)
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
            .sheet(isPresented: $isShowingCreateTaskSheet) {
                EditTaskView(
                    formMode: .scheduled,
                    initialTitle: prefillTitle,
                    defaultDueDate: createTaskDueDateOverride ?? dayID(for: selectedDate),
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
                .id(createTaskFormInstanceID)
                .environmentObject(appRouter)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $viewModel.prefilledTaskForAI) { draft in
                EditTaskView(
                    formMode: .scheduled,
                    initialTitle: draft.title,
                    initialNote: draft.description,
                    initialLocationName: draft.locationName,
                    initialDueDate: draft.dueDate,
                    initialAttachmentImages: [draft.attachmentImage],
                    defaultDueDate: draft.dueDate.map { dayID(for: $0) } ?? dayID(for: selectedDate),
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
                .id(aiPrefillFormInstanceID)
                .environmentObject(appRouter)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $viewModel.isShowingCamera) {
                CameraPicker(
                    onImageCaptured: { source, originalImage, compressedData in
                        viewModel.isShowingCamera = false
                        Task {
                            await viewModel.processCapturedImage(
                                compressedData,
                                originalImage: originalImage,
                                source: source
                            )
                        }
                    },
                    onCancel: {
                        viewModel.isShowingCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .alert("识图失败", isPresented: aiErrorAlertBinding) {
                Button("好", role: .cancel) {
                    viewModel.aiProcessingError = nil
                }
            } message: {
                if let message = viewModel.aiProcessingError {
                    Text(message)
                }
            }
            .task {
                viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
                await viewModel.loadTasks()
                openPendingScheduledTaskIfNeeded()
                Task {
                    await refreshCurrentMembershipRole()
                    await viewModel.setupRealtimeListener()
                }
            }
            .onDisappear {
                Task {
                    await viewModel.stopRealtimeListener()
                }
            }
            .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
                viewModel.setHouseholdContext(newValue)
                Task {
                    await viewModel.loadTasks()
                    openPendingScheduledTaskIfNeeded()
                    Task {
                        await refreshCurrentMembershipRole()
                        await viewModel.setupRealtimeListener()
                    }
                }
            }
            .onChange(of: appRouter.selectedMembershipId) { _, _ in
                Task {
                    await refreshCurrentMembershipRole()
                }
            }
            .onChange(of: currentViewMode) { _, mode in
                if mode == .list {
                    viewModel.noteVisibleMonth(containing: Date())
                    listScrollToken += 1
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
            calendarTopBar

            Group {
                switch currentViewMode {
                case .list:
                    TaskModeListView(
                        viewModel: viewModel,
                        listScrollToken: listScrollToken,
                        onTaskTap: { taskForDetailSheet = $0 },
                        onRefresh: refreshTasks
                    )
                case .day:
                    TaskModeDayView(
                        selectedDate: $selectedDate,
                        viewModel: viewModel,
                        onTaskSelect: { taskForDetailSheet = $0 },
                        onQuickCreate: { prefill, dueOverride in
                            prefillTitle = prefill
                            createTaskDueDateOverride = dueOverride
                            createTaskFormInstanceID = UUID()
                            isShowingCreateTaskSheet = true
                        },
                        onRefresh: refreshTasks
                    )
                case .threeDay, .week, .month, .year:
                    Text(AppLocalized.string("开发中...", locale: locale))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            quickTaskInputBar
        }
    }

    private var quickTaskInputBar: some View {
        HStack(spacing: 10) {
            TextField("输入任务标题…", text: $quickTaskInput)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(submitQuickTaskInput)

            Button(action: openCameraIfAvailable) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAIProcessing)
            .accessibilityLabel("拍照创建任务")
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
                Text("AI 正在阅读您的图片...")
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

    private func submitQuickTaskInput() {
        let trimmed = quickTaskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        quickTaskInput = ""
        openCreateTask(prefill: trimmed)
    }

    private func openCameraIfAvailable() {
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

    private var calendarTopBar: some View {
        HStack(spacing: 0) {
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            VStack(spacing: 4) {
                Button {
                    groupSwitcher.showSwitchGroupDialog = true
                } label: {
                    HStack(spacing: 4) {
                        Text(GroupSwitcherData.currentName(for: appRouter))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)

                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("群组，\(GroupSwitcherData.currentName(for: appRouter))")
                .accessibilityHint("轻点以切换群组")

                Button {
                    isShowingCalendarSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Text(navigationMonthYearTitle)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            Button {
                openCreateTask(prefill: "")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.ColorToken.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var navigationReferenceDate: Date {
        switch currentViewMode {
        case .list:
            return viewModel.currentVisibleDate
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
        prefillTitle = prefill
        createTaskDueDateOverride = defaultDueDateOverride
        createTaskFormInstanceID = UUID()
        isShowingCreateTaskSheet = true
    }

    private func dayID(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
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
