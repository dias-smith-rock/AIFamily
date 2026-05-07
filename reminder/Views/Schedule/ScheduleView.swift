import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

struct ScheduleView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeScheduleViewModel()
    @State private var selectedDate: Date = Date()
    @State private var isShowingCalendarSheet = false
    @State private var taskForDetailSheet: FamilyTask?
    @State private var currentMembershipRole: MembershipRole = .member
    let onRequestAIInput: () -> Void

    init(onRequestAIInput: @escaping () -> Void = {}) {
        self.onRequestAIInput = onRequestAIInput
    }

    private enum TimelineItem: Identifiable {
        case task(FamilyTask)
        case now(Date)

        var id: String {
            switch self {
            case let .task(task):
                return "task-\(task.id)"
            case let .now(date):
                return "now-\(date.timeIntervalSince1970)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    weekSection
                    timelineSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
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
            .task {
                viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
                await refreshCurrentMembershipRole()
                await viewModel.loadTasks()
            }
            .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
                viewModel.setHouseholdContext(newValue)
                Task {
                    await refreshCurrentMembershipRole()
                    await viewModel.loadTasks()
                }
            }
            .onChange(of: appRouter.selectedMembershipId) { _, _ in
                Task {
                    await refreshCurrentMembershipRole()
                }
            }
            .onChange(of: selectedDate) { _, _ in
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
                NavigationLink {
                    CreateTaskView(onSaveSuccess: { createdDueDate in
                        selectedDate = createdDueDate
                        Task {
                            await viewModel.loadTasks()
                        }
                    })
                    .environmentObject(appRouter)
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
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(weekDates, id: \.self) { date in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = date
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 12, weight: .semibold))
                            Text(date.formatted(.dateTime.day()))
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(isSelected(date) ? .white : .primary)
                        .frame(width: 50, height: 72)
                        .background(isSelected(date) ? Color.black : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var timelineSection: some View {
        LazyVStack(spacing: 16) {
            if viewModel.isLoading {
                ProgressView("正在加载任务...")
                    .frame(maxWidth: .infinity, minHeight: 220)
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
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if timelineItems.isEmpty {
                ContentUnavailableView(
                    "暂无任务",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("这一天还没有安排，点击右上角 + 创建任务。")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                    switch item {
                    case let .task(task):
                        timelineTaskRow(task: task, index: index)
                    case let .now(now):
                        currentTimeRow(now: now)
                    }
                }
            }
        }
    }

    private func timelineTaskRow(task: FamilyTask, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            timelineRail(
                timeText: taskDisplayDate(task).formatted(date: .omitted, time: .shortened),
                showTop: index > 0,
                showBottom: index < timelineItems.count - 1,
                dotColor: .secondary
            )
            TaskRowView(task: task, profiles: taskProfiles(for: task))
                .onTapGesture {
                    taskForDetailSheet = task
                }
        }
    }

    private func currentTimeRow(now: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 56, alignment: .trailing)

            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(.red.opacity(0.9))
                    .frame(height: 2)
            }
        }
    }

    private func timelineRail(
        timeText: String,
        showTop: Bool,
        showBottom: Bool,
        dotColor: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(timeText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

            ZStack {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(showTop ? Color.secondary.opacity(0.25) : .clear)
                        .frame(width: 1, height: 24)
                    Rectangle()
                        .fill(showBottom ? Color.secondary.opacity(0.25) : .clear)
                        .frame(width: 1, height: 84)
                }
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 10)
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
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: selectedDate)
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

    private var timelineItems: [TimelineItem] {
        var items = selectedDateTasks.map { TimelineItem.task($0) }
        guard Calendar.current.isDateInToday(selectedDate) else {
            return items
        }
        let now = Date()
        let insertionIndex = selectedDateTasks.firstIndex { task in
            taskDisplayDate(task) > now
        } ?? selectedDateTasks.count
        items.insert(.now(now), at: insertionIndex)
        return items
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        return (-7...13).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: selectedDate)
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(headerText)
                    .font(.title2.bold())
                Spacer()
                Button("Today") {
                    selectedDate = Date()
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

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(monthCells.indices, id: \.self) { index in
                    if let date = monthCells[index] {
                        Button {
                            selectedDate = date
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
        }
        .padding(16)
    }

    private var headerText: String {
        selectedDate.formatted(.dateTime.month(.wide).year())
    }

    private var monthCells: [Date?] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var cells: [Date?] = []
        var date = firstWeek.start
        while date < lastWeek.end {
            if calendar.isDate(date, equalTo: selectedDate, toGranularity: .month) {
                cells.append(date)
            } else {
                cells.append(nil)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return cells
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }
}

#Preview {
    ScheduleView()
        .environmentObject(AppRouter())
}
