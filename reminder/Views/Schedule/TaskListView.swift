import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

/// 任务 / 日程主页：顶栏日历风格导航 + 多视图模式路由。
struct TaskListView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
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

    @StateObject private var orgRoutingViewModel = AppViewModels.makeOrgRoutingViewModel()
    @State private var isShowingCreateOrganizationSheet = false
    @State private var newOrganizationName = ""
    @State private var createOrganizationError: String?

    var body: some View {
        NavigationStack {
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
                CreateTaskView(
                    initialTitle: prefillTitle,
                    defaultDueDate: createTaskDueDateOverride ?? dayID(for: selectedDate),
                    defaultAllDayForNewTask: true,
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
            .task {
                viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
                await refreshCurrentMembershipRole()
                await viewModel.loadTasks()
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
                    await refreshCurrentMembershipRole()
                    await viewModel.loadTasks()
                    await viewModel.setupRealtimeListener()
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
            .sheet(isPresented: $isShowingCreateOrganizationSheet) {
                CreateOrganizationSheet(
                    organizationName: $newOrganizationName,
                    inputError: $createOrganizationError,
                    isSubmitting: orgRoutingViewModel.isCreating,
                    onSubmit: {
                        await submitCreateOrganization()
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .appLocaleEnvironment(using: appSettings)
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
                OrganizationSwitcherControl(
                    isShowingCreateOrganization: $isShowingCreateOrganizationSheet
                )

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
        for task in viewModel.tasks {
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
    private func submitCreateOrganization() async {
        createOrganizationError = nil
        let normalizedName = newOrganizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            createOrganizationError = "Organization name cannot be empty."
            return
        }

        guard let createdHouseholdId = await orgRoutingViewModel.createHousehold(displayName: normalizedName) else {
            createOrganizationError = orgRoutingViewModel.errorMessage
            return
        }

        newOrganizationName = ""
        isShowingCreateOrganizationSheet = false
        appRouter.preferHouseholdOnNextRefresh(createdHouseholdId)
        await appRouter.refreshStateFromBackend()
        viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
        await refreshCurrentMembershipRole()
        await viewModel.loadTasks()
        await viewModel.setupRealtimeListener()
    }

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
}
