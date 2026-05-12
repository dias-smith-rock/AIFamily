import SwiftUI
import Kingfisher

#if canImport(Supabase)
import Supabase
#endif

private enum AllDayCardSlotWidthPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScheduleView: View {
    private let taskFlowTimeColumnWidth: CGFloat = 50
    private let taskFlowCompactGapHeight: CGFloat = 40
    private let taskFlowLongIdleThreshold: TimeInterval = 3600
    /// 未收到 ScrollView 宽度前占位，避免首张卡片过窄（约等于常见屏宽减去左右边距与时间列）。
    private let allDayCardFallbackWidth: CGFloat = 300

    private var resolvedAllDayCardWidth: CGFloat {
        allDayCardSlotWidth > 8 ? allDayCardSlotWidth : allDayCardFallbackWidth
    }

    /// 固定锚点：用于把 TabView 页码映射成真实自然周（与 `weekOffset` 搭配使用）。
    @State private var weekEpochStart: Date = ScheduleView.startOfWeek(for: Date())
    /// 相对 `weekEpochStart` 的周偏移；与 `TabView` selection 绑定。
    @State private var weekOffset: Int = 0

    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeScheduleViewModel()
    @State private var selectedDate: Date = Date()
    @State private var isShowingCalendarSheet = false
    @State private var isShowingCreateTaskSheet = false
    @State private var createTaskFormInstanceID = UUID()
    @State private var prefillTitle = ""
    /// 新建任务默认「开始日」：`nil` 表示使用周历当前选中的 `selectedDate`。
    @State private var createTaskDueDateOverride: Date?
    @State private var taskForDetailSheet: FamilyTask?
    @State private var currentMembershipRole: MembershipRole = .member
    /// 横向全天列表可视区域宽度，用于单卡宽度与下方 `TaskCardView` 一致。
    @State private var allDayCardSlotWidth: CGFloat = 0
    let onRequestAIInput: () -> Void

    init(onRequestAIInput: @escaping () -> Void = {}) {
        self.onRequestAIInput = onRequestAIInput
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                headerSection
                weekSection
                    .padding(.horizontal, 16)
                if allDayTasks.isEmpty == false {
                    allDayTasksPinnedStrip
                }
                timelineSection
            }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .preference(key: ScheduleSelectedDayPreferenceKey.self, value: dayID(for: selectedDate))
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
                    defaultDueDate: createTaskDueDateOverride ?? dayID(for: selectedDate),
                    defaultAllDayForNewTask: true,
                    onSaveSuccess: { createdDueDate in
                        selectedDate = dayID(for: createdDueDate)
                        Task {
                            await viewModel.loadTasks()
                        }
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
            .onChange(of: selectedDate) { _, _ in
                let normalized = dayID(for: selectedDate)
                if selectedDate != normalized {
                    selectedDate = normalized
                    return
                }
                let targetWeekPage = weekOffsetForDate(normalized)
                if weekOffset != targetWeekPage {
                    weekOffset = targetWeekPage
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
        GlobalHeaderView {
            Button {
                isShowingCalendarSheet = true
            } label: {
                HStack(spacing: 8) {
                    Text(selectedDateTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } trailing: {
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
        TabView(selection: $weekOffset) {
            ForEach(Self.weekPageRange, id: \.self) { offset in
                weekStrip(for: offset)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 84, alignment: .top)
        .onAppear {
            weekOffset = weekOffsetForDate(selectedDate)
        }
    }

    /// 根据周偏移生成当周 7 天（从系统 locale 的「每周起始日」算起）。
    private func daysInWeek(weekOffset offset: Int) -> [Date] {
        let cal = Calendar.current
        guard let weekStart = cal.date(byAdding: .day, value: offset * 7, to: weekEpochStart) else {
            return []
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// `date` 所在自然周相对 `weekEpochStart` 是第几周。
    private func weekOffsetForDate(_ date: Date) -> Int {
        let targetWeekStart = Self.startOfWeek(for: dayID(for: date))
        let days = Calendar.current.dateComponents([.day], from: weekEpochStart, to: targetWeekStart).day ?? 0
        return days / 7
    }

    private func weekStrip(for offset: Int) -> some View {
        let days = daysInWeek(weekOffset: offset)
        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { loopDate in
                weekDayCell(for: loopDate)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekDayCell(for loopDate: Date) -> some View {
        let loopDay = dayID(for: loopDate)
        let selected = loopDay == selectedDay
        let isToday = loopDay == dayID(for: Date())
        let count = taskCount(for: loopDate)
        return Button {
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
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(selected ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 36, maxHeight: 36)
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
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
    }

    private static let weekPageRange = -500...500

    private static func startOfWeek(for date: Date) -> Date {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: day)
        let firstWeekday = cal.firstWeekday
        let delta = (weekday - firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -delta, to: day) ?? day
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
                                if timedTasks.isEmpty == false {
                                    ScheduleTaskAnchorFlow(
                                        timedTasks: timedTasks,
                                        selectedCalendarDay: selectedDay,
                                        timeColumnWidth: taskFlowTimeColumnWidth,
                                        compactGapHeight: taskFlowCompactGapHeight,
                                        longIdleThreshold: taskFlowLongIdleThreshold,
                                        taskAnchor: { taskDisplayDate($0) },
                                        taskEnd: { taskEndDate($0) },
                                        onTaskTap: { taskForDetailSheet = $0 },
                                        card: { task in
                                            TaskRowView(
                                                task: task,
                                                forWhomAvatars: forWhomAvatarSources(for: task),
                                                assigneeLabel: assigneeLabel(for: task)
                                            )
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                        .onAppear {
                            scrollTaskAnchorFlowToInitial(proxy: proxy, animated: false)
                        }
                        .onChange(of: selectedDate) { _, _ in
                            scrollTaskAnchorFlowToInitial(proxy: proxy)
                        }
                    }

                    if selectedDateTasks.isEmpty {
                        emptyStateView()
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 周历下方置顶：`is_all_day` 任务专用紧凑卡片（标题 + 为了谁），横向滑动。
    /// 左侧「全天」与时间列同宽左对齐；卡片宽度与锚点行右侧任务卡一致（随 ScrollView 可视宽度）。
    private var allDayTasksPinnedStrip: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("全天")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: taskFlowTimeColumnWidth, alignment: .leading)
                .padding(.top, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allDayTasks) { task in
                        AllDayTaskRowView(
                            task: task,
                            forWhomAvatars: forWhomAvatarSources(for: task)
                        )
                        .frame(width: resolvedAllDayCardWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            taskForDetailSheet = task
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AllDayCardSlotWidthPreference.self,
                        value: proxy.size.width
                    )
                }
            )
            .onPreferenceChange(AllDayCardSlotWidthPreference.self) { width in
                if abs(width - allDayCardSlotWidth) > 0.5 {
                    allDayCardSlotWidth = width
                }
            }
        }
        .padding(.horizontal, 16)
        /// 与下方「08:32」首行之间的区块留白（叠加上层 `VStack` spacing 10 ≈ 22–24pt）。
        .padding(.bottom, 14)
    }

    private func taskEndDate(_ task: FamilyTask) -> Date {
        let cal = Calendar.current
        let start = taskDisplayDate(task)
        if let end = task.endDatetime {
            return end
        }
        return cal.date(byAdding: .hour, value: 1, to: start) ?? start
    }

    private func scrollTaskAnchorFlowToInitial(proxy: ScrollViewProxy, animated: Bool = true) {
        guard timedTasks.isEmpty == false else { return }
        let cal = Calendar.current
        let viewingToday = cal.isDateInToday(selectedDay)
        let sorted = timedTasks.sorted { taskDisplayDate($0) < taskDisplayDate($1) }
        guard let first = sorted.first else { return }
        let firstID = "task-\(first.id.uuidString)"

        let action = {
            if viewingToday {
                proxy.scrollTo(ScheduleAnchorFlowScrollIDs.nowMarker, anchor: .center)
            } else {
                proxy.scrollTo(firstID, anchor: .top)
            }
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
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
                actionChip(emoji: "✨", title: "Family Dinner", dueDateKind: .selectedDay)
                actionChip(emoji: "🛒", title: "Grocery List", dueDateKind: .dayAfterSelected)
                actionChip(emoji: "🧸", title: "Kids Activity", dueDateKind: .nextSaturdayFromSelected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -50)
    }

    /// Emoji 与标题样式隔离，避免环境里的 `.foregroundStyle` 把 Emoji 压成单色。
    private func actionChip(emoji: String, title: String, dueDateKind: QuickCreateDueDateKind = .selectedDay) -> some View {
        Button {
            openCreateTask(prefill: title, defaultDueDateOverride: defaultDueDate(for: dueDateKind))
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

    private func dayID(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private enum QuickCreateDueDateKind {
        /// 与顶栏「+」一致：当前选中日。
        case selectedDay
        /// 购物清单：选中日的次日 0 点。
        case dayAfterSelected
        /// 亲子活动：从选中日（含）起往后找第一个周六（自然周）。
        case nextSaturdayFromSelected
    }

    private func defaultDueDate(for kind: QuickCreateDueDateKind) -> Date? {
        switch kind {
        case .selectedDay:
            return nil
        case .dayAfterSelected:
            return calendarDayByAdding(1, to: selectedDate)
        case .nextSaturdayFromSelected:
            return nextSaturdayOnOrAfter(selectedDate)
        }
    }

    private func calendarDayByAdding(_ days: Int, to anchor: Date) -> Date {
        let cal = Calendar.current
        let base = dayID(for: anchor)
        guard let shifted = cal.date(byAdding: .day, value: days, to: base) else { return base }
        return cal.startOfDay(for: shifted)
    }

    /// `weekday` 与 `Calendar.Component.weekday` 一致（如美国历：1=周日 … 7=周六）。
    private func nextSaturdayOnOrAfter(_ anchor: Date) -> Date {
        let cal = Calendar.current
        let base = dayID(for: anchor)
        for offset in 0..<14 {
            guard let d = cal.date(byAdding: .day, value: offset, to: base) else { continue }
            if cal.component(.weekday, from: d) == 7 {
                return cal.startOfDay(for: d)
            }
        }
        return base
    }

    private func openCreateTask(prefill: String, defaultDueDateOverride: Date? = nil) {
        prefillTitle = prefill
        createTaskDueDateOverride = defaultDueDateOverride
        createTaskFormInstanceID = UUID()
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

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func taskDisplayDate(_ task: FamilyTask) -> Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private func orderedTargetProfileIDs(for task: FamilyTask) -> [UUID] {
        var ordered: [UUID] = []
        var seen = Set<UUID>()
        if let multi = task.targetProfileIds {
            for id in multi where seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        if let single = task.targetProfileId, seen.insert(single).inserted {
            ordered.append(single)
        }
        return ordered
    }

    private func forWhomAvatarSources(for task: FamilyTask) -> [TaskCardAvatarSource] {
        let ids = orderedTargetProfileIDs(for: task)
        guard ids.isEmpty == false else { return [] }
        let profileById = Dictionary(uniqueKeysWithValues: viewModel.familyProfiles.map { ($0.id, $0) })
        return ids.compactMap { id in
            guard let profile = profileById[id] else { return nil }
            return TaskCardAvatarSource(
                id: profile.id,
                displayName: profile.name,
                imageURL: profile.avatarUrl.flatMap { URL(string: $0) }
            )
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
        if task.involvesWholeHousehold {
            return "所有人"
        }
        guard let ids = task.involvedMemberIds, ids.isEmpty == false else {
            return "所有人"
        }
        let memberById = Dictionary(uniqueKeysWithValues: viewModel.householdMembers.map { ($0.id, $0) })
        let names = ids.compactMap { id in memberById[id]?.nickname }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        if names.isEmpty {
            return ids.count == 1 ? "成员" : "\(ids.count) 人"
        }
        return names.joined(separator: "、")
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

private enum TaskEmergencyDialURLs {
    static func sanitizedPhone(_ raw: String) -> String {
        raw.filter { character in
            character.isWhitespace == false && character.isNewline == false
        }
    }

    static func telURL(phone raw: String) -> URL? {
        let s = sanitizedPhone(raw)
        guard s.isEmpty == false else { return nil }
        if let url = URL(string: "tel://\(s)") {
            return url
        }
        let encoded = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        return URL(string: "tel://\(encoded)")
    }

    static func faceTimeURL(phone raw: String) -> URL? {
        let s = sanitizedPhone(raw)
        guard s.isEmpty == false else { return nil }
        if let url = URL(string: "facetime://\(s)") {
            return url
        }
        let encoded = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        return URL(string: "facetime://\(encoded)")
    }
}

private struct TaskRowView: View {
    let task: FamilyTask
    let forWhomAvatars: [TaskCardAvatarSource]
    let assigneeLabel: String

    var body: some View {
        TaskCardView(task: task, forWhomAvatars: forWhomAvatars, assigneeLabel: assigneeLabel)
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
