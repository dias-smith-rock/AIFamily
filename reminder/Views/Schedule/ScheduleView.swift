import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

struct ScheduleView: View {
    private let hourHeight: CGFloat = 100
    private let timeAxisWidth: CGFloat = 60

    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeScheduleViewModel()
    @State private var selectedDate: Date = Date()
    @State private var isShowingCalendarSheet = false
    @State private var isShowingCreateTaskSheet = false
    @State private var prefillTitle = ""
    @State private var taskForDetailSheet: FamilyTask?
    @State private var currentMembershipRole: MembershipRole = .member
    let onRequestAIInput: () -> Void

    init(onRequestAIInput: @escaping () -> Void = {}) {
        self.onRequestAIInput = onRequestAIInput
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                weekSection
                    .padding(.horizontal, 16)
                timelineSection
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
                    onSaveSuccess: { createdDueDate in
                        selectedDate = dayID(for: createdDueDate)
                        Task {
                            await viewModel.loadTasks()
                        }
                    }
                )
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
            .onChange(of: selectedDate) { _, _ in
                let normalized = dayID(for: selectedDate)
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
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            Button {
                isShowingCalendarSheet = true
            } label: {
                HStack(spacing: 8) {
                    Text(selectedDateTitle)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                avatarBadge
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
            }
        }
    }

    private var weekSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(weekDates, id: \.self) { loopDate in
                        let loopDay = dayID(for: loopDate)
                        let selected = loopDay == selectedDay
                        let isToday = loopDay == dayID(for: Date())
                        let count = taskCount(for: loopDate)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = loopDay
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(loopDate.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(selected ? AppTheme.ColorToken.accent : .secondary)
                                Text(loopDate.formatted(.dateTime.day()))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(selected ? .white : .primary)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Group {
                                            if selected {
                                                Circle()
                                                    .fill(AppTheme.ColorToken.accent)
                                            } else if isToday {
                                                Circle()
                                                    .stroke(AppTheme.ColorToken.accent, lineWidth: 2)
                                            }
                                        }
                                    )
                                HStack(spacing: 3) {
                                    if count >= 1 {
                                        Circle()
                                            .fill(.blue)
                                            .frame(width: 4, height: 4)
                                    }
                                    if count >= 3 {
                                        Circle()
                                            .fill(.orange)
                                            .frame(width: 4, height: 4)
                                    }
                                    if count >= 5 {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 4, height: 4)
                                    }
                                }
                                .frame(height: 6)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .id(dayID(for: loopDate))
                    }
                }
            }
            .onAppear {
                scrollWeekToSelected(with: proxy, animated: false)
            }
            .onChange(of: selectedDate) { _, _ in
                scrollWeekToSelected(with: proxy)
            }
        }
        .frame(height: 84, alignment: .top)
    }

    private var timelineSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("正在加载任务...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重新加载") {
                        Task {
                            await viewModel.loadTasks()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 12) {
                                if allDayTasks.isEmpty == false {
                                    allDaySection
                                }

                                ZStack(alignment: .topLeading) {
                                    timeGrid
                                    taskCardsLayer
                                    if Calendar.current.isDateInToday(selectedDate) {
                                        currentTimeIndicator
                                    }
                                }
                                .frame(height: hourHeight * 24, alignment: .topLeading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                        .onAppear {
                            scrollToFocusedHour(with: proxy, animated: false)
                        }
                        .onChange(of: selectedDate) { _, _ in
                            scrollToFocusedHour(with: proxy)
                        }
                    }

                    if timedTasks.isEmpty {
                        emptyStateView()
                            .padding(.leading, timeAxisWidth)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var timeGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: timeAxisWidth, alignment: .topTrailing)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 1)

                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private var allDaySection: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 6) {
                Text("全天")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())

                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 1, height: 14)
            }
            .frame(width: timeAxisWidth)

            if allDayTasks.count <= 2 {
                VStack(spacing: 8) {
                    ForEach(allDayTasks) { task in
                        TaskRowView(task: task, profiles: taskProfiles(for: task))
                            .onTapGesture {
                                taskForDetailSheet = task
                            }
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allDayTasks) { task in
                            TaskRowView(task: task, profiles: taskProfiles(for: task))
                                .frame(width: 220)
                                .onTapGesture {
                                    taskForDetailSheet = task
                                }
                        }
                    }
                }
            }
        }
    }

    private var taskCardsLayer: some View {
        GeometryReader { geo in
            let cardWidth = max(140, geo.size.width - timeAxisWidth - 16)
            ForEach(timedTasks) { task in
                TaskRowView(task: task, profiles: taskProfiles(for: task))
                    .frame(width: cardWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(x: timeAxisWidth + 10, y: yOffset(for: taskDisplayDate(task)))
                    .onTapGesture {
                        taskForDetailSheet = task
                    }
            }
        }
    }

    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.13))
                    .frame(width: 120, height: 120)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 8) {
                Text("No tasks scheduled today")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text("Enjoy your family time, or plan something new.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                actionChip(emoji: "✨", title: "Family Dinner")
                actionChip(emoji: "🛒", title: "Grocery List")
                actionChip(emoji: "🧸", title: "Kids Activity")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -50)
    }

    /// Emoji 与标题样式隔离，避免环境里的 `.foregroundStyle` 把 Emoji 压成单色。
    private func actionChip(emoji: String, title: String) -> some View {
        Button {
            openCreateTask(prefill: title)
        } label: {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 22))
                    .fixedSize()
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppTheme.ColorToken.surfaceMuted)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var currentTimeIndicator: some View {
        let now = Date()
        return HStack(alignment: .center, spacing: 6) {
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: timeAxisWidth, alignment: .trailing)

            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            Rectangle()
                .fill(.red)
                .frame(height: 1.5)
        }
        .offset(y: yOffset(for: now))
    }

    private func yOffset(for date: Date) -> CGFloat {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let startHour = components.hour ?? 0
        let startMinute = components.minute ?? 0
        return CGFloat(startHour) * hourHeight + (CGFloat(startMinute) / 60.0) * hourHeight
    }

    private func scrollToFocusedHour(with proxy: ScrollViewProxy, animated: Bool = true) {
        let calendar = Calendar.current
        let targetHour: Int
        if calendar.isDateInToday(selectedDate) {
            let currentHour = calendar.component(.hour, from: Date())
            targetHour = max(0, currentHour - 1)
        } else {
            if let firstTaskDate = timedTasks.first.map(taskDisplayDate) {
                targetHour = max(0, min(23, calendar.component(.hour, from: firstTaskDate)))
            } else {
                targetHour = 8
            }
        }
        let action = {
            proxy.scrollTo(targetHour, anchor: .top)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
        }
    }

    private var avatarBadge: some View {
        Circle()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
    }

    private var selectedDateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.calendar = Calendar.current
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: selectedDay)
    }

    private var selectedDateTasks: [FamilyTask] {
        viewModel.tasks
            .filter { task in
                Calendar.current.isDate(taskDisplayDate(task), inSameDayAs: selectedDate)
            }
            .sorted { lhs, rhs in
                taskDisplayDate(lhs) < taskDisplayDate(rhs)
            }
    }

    private var allDayTasks: [FamilyTask] {
        selectedDateTasks.filter(\.isAllDay)
    }

    private var timedTasks: [FamilyTask] {
        selectedDateTasks.filter { $0.isAllDay == false }
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        return (-14...14).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: selectedDay)
        }
    }

    private func dayID(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func openCreateTask(prefill: String) {
        prefillTitle = prefill
        isShowingCreateTaskSheet = true
    }

    private var selectedDay: Date {
        dayID(for: selectedDate)
    }

    private func taskCount(for date: Date) -> Int {
        viewModel.tasks.reduce(into: 0) { result, task in
            if Calendar.current.isDate(taskDisplayDate(task), inSameDayAs: date) {
                result += 1
            }
        }
    }

    private func scrollWeekToSelected(with proxy: ScrollViewProxy, animated: Bool = true) {
        let targetID = dayID(for: selectedDate)
        let action = {
            proxy.scrollTo(targetID, anchor: .center)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
        }
    }

    private var monthTaskDots: [Date: [Color]] {
        var result: [Date: [Color]] = [:]
        let monthTasks = viewModel.tasks.filter { task in
            Calendar.current.isDate(taskDisplayDate(task), equalTo: selectedDate, toGranularity: .month)
        }
        for task in monthTasks {
            let day = Calendar.current.startOfDay(for: taskDisplayDate(task))
            let color = statusColor(for: task.status)
            var colors = result[day, default: []]
            if colors.contains(where: { $0.description == color.description }) == false {
                colors.append(color)
            }
            result[day] = colors
        }

        if result.isEmpty {
            let today = Calendar.current.startOfDay(for: Date())
            result[today] = [.blue, .red]
            if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) {
                result[tomorrow] = [.green]
            }
        }
        return result
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func taskDisplayDate(_ task: FamilyTask) -> Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private func taskProfiles(for task: FamilyTask) -> [HouseholdMembership] {
        let profileIds = task.involvedMemberIds ?? []
        return profileIds.compactMap { id in
            HouseholdMembership.mockMembers.first(where: { $0.id == id })
        }
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
        guard let ids = task.involvedMemberIds, ids.isEmpty == false else {
            return "所有人"
        }
        if ids.count == 1 {
            return HouseholdMembership.mockMembers.first(where: { $0.id == ids[0] })?.nickname ?? "成员"
        }
        return "\(ids.count) 人"
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
}

private struct TaskRowView: View {
    let task: FamilyTask
    let profiles: [HouseholdMembership]

    var body: some View {
        HStack(spacing: 0) {
            statusColor
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(2)
                        if task.isAllDay == false {
                            Label(taskTimeText, systemImage: "clock")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if let estimatedCost = task.estimatedCost, estimatedCost > 0 {
                            Text("¥\(estimatedCost)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: -8) {
                        ForEach(Array(profiles.prefix(3).enumerated()), id: \.offset) { _, profile in
                            AvatarView(profile: profile)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text(statusTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var statusColor: Color {
        switch task.status {
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

    private var statusTitle: String {
        switch task.status {
        case .new:
            return "待接受"
        case .accepted, .inProgress:
            return "进行中"
        case .completed:
            return "已完成"
        case .issue:
            return "有问题"
        case .expired:
            return "已过期"
        case .failed:
            return "失败"
        case .cancelled:
            return "已取消"
        }
    }

    private var taskTimeText: String {
        let date = task.dueDate ?? task.originalDueDate ?? task.createdAt
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct AvatarView: View {
    let profile: HouseholdMembership

    var body: some View {
        ZStack {
            if let avatarString = profile.avatarUrl, let url = URL(string: avatarString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white, lineWidth: 1.6)
        )
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .overlay {
                Text(String(profile.nickname.prefix(1)))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
            }
    }
}

private struct CalendarSheetView: View {
    @Binding var selectedDate: Date
    let monthTaskDots: [Date: [Color]]
    @Environment(\.dismiss) private var dismiss
    @State private var monthOffset = 0
    @State private var headerMonth: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    init(selectedDate: Binding<Date>, monthTaskDots: [Date: [Color]]) {
        self._selectedDate = selectedDate
        self.monthTaskDots = monthTaskDots
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedDate.wrappedValue)) ?? selectedDate.wrappedValue
        self._headerMonth = State(initialValue: monthStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(headerText)
                    .font(.title2.bold())
                Spacer()
                Button("Today") {
                    selectedDate = dayID(Date())
                    withAnimation(.easeInOut(duration: 0.25)) {
                        monthOffset = 0
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Circle())
                }
            }

            HStack {
                ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            TabView(selection: $monthOffset) {
                ForEach(-12...12, id: \.self) { offset in
                    let month = monthDate(for: offset)
                    let cells = monthGridCells(for: month)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(cells.indices, id: \.self) { index in
                            if let date = cells[index] {
                                Button {
                                    selectedDate = dayID(date)
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(date.formatted(.dateTime.day()))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(isSelected(date) ? .white : .primary)

                                        HStack(spacing: 3) {
                                            let dots = monthTaskDots[Calendar.current.startOfDay(for: date)] ?? []
                                            ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, color in
                                                Circle()
                                                    .fill(isSelected(date) ? Color.white : color)
                                                    .frame(width: 5, height: 5)
                                            }
                                        }
                                        .frame(height: 8)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(isSelected(date) ? Color.black : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear
                                    .frame(height: 44)
                            }
                        }
                    }
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: monthOffset) { _, newOffset in
                headerMonth = monthDate(for: newOffset)
            }
            .onChange(of: selectedDate) { _, newDate in
                let visibleOffset = monthOffsetDateDifference(from: newDate)
                if (-12...12).contains(visibleOffset), visibleOffset != monthOffset {
                    monthOffset = visibleOffset
                    headerMonth = monthDate(for: visibleOffset)
                }
            }
        }
        .padding(16)
    }

    private var headerText: String {
        headerMonth.formatted(.dateTime.month(.wide).year())
    }

    private func monthGridCells(for monthBaseDate: Date) -> [Date?] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: monthBaseDate)
        else {
            return []
        }

        let firstDay = monthInterval.start
        let totalDays = calendar.dateComponents([.day], from: firstDay, to: monthInterval.end).day ?? 0
        let weekdayOfFirstDay = calendar.component(.weekday, from: firstDay)
        let leadingSlots = (weekdayOfFirstDay - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingSlots)
        for dayOffset in 0..<totalDays {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return cells
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func monthDate(for offset: Int) -> Date {
        let calendar = Calendar.current
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return calendar.date(byAdding: .month, value: offset, to: currentMonthStart) ?? currentMonthStart
    }

    private func monthOffsetDateDifference(from date: Date) -> Int {
        let calendar = Calendar.current
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let targetMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let diff = calendar.dateComponents([.month], from: currentMonthStart, to: targetMonthStart).month ?? 0
        return max(-12, min(12, diff))
    }

    private func dayID(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}

#Preview {
    ScheduleView()
        .environmentObject(AppRouter())
}
