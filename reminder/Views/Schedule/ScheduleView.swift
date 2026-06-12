import SwiftUI
import Kingfisher

/// Day 模式：周历条 + 全天条 + 锚点时间轴（由 `TaskListView` 嵌入）。
struct TaskModeDayView: View {
    @Environment(\.locale) private var locale

    private let taskFlowCompactGapHeight: CGFloat = ScheduleTimelineMetrics.taskFlowGapHeight
    private let taskFlowLongIdleThreshold: TimeInterval = 3600
    /// 未收到 ScrollView 宽度前占位，避免首张卡片过窄（约等于常见屏宽减去左右边距与时间列）。
    private let allDayCardFallbackWidth: CGFloat = 300

    private var resolvedAllDayCardWidth: CGFloat {
        allDayCardSlotWidth > 8 ? allDayCardSlotWidth : allDayCardFallbackWidth
    }

    /// 固定锚点：用于把 TabView 页码映射成真实自然周（与 `weekOffset` 搭配使用）。
    @State private var weekEpochStart: Date = TaskModeDayView.startOfWeek(for: Date())
    /// 相对 `weekEpochStart` 的周偏移；与 `TabView` selection 绑定。
    @State private var weekOffset: Int = 0

    @ObservedObject var viewModel: ScheduleViewModel
    @Binding var selectedDate: Date

    /// 横向全天列表可视区域宽度，用于单卡宽度与下方 `TaskCardView` 一致。
    @State private var allDayCardSlotWidth: CGFloat = 0
    @State private var daySlideInsertionEdge: Edge = .trailing
    @State private var interactiveDayDragOffset: CGFloat = 0

    private let daySwipeSpring = Animation.spring(response: 0.34, dampingFraction: 0.88)
    private let dayDragMaxOffset: CGFloat = 96

    let onTaskSelect: (FamilyTask) -> Void
    let onQuickCreate: (String, Date?) -> Void
    let onRefresh: (() async -> Void)?

    init(
        selectedDate: Binding<Date>,
        viewModel: ScheduleViewModel,
        onTaskSelect: @escaping (FamilyTask) -> Void,
        onQuickCreate: @escaping (String, Date?) -> Void,
        onRefresh: (() async -> Void)? = nil
    ) {
        self._selectedDate = selectedDate
        self.viewModel = viewModel
        self.onTaskSelect = onTaskSelect
        self.onQuickCreate = onQuickCreate
        self.onRefresh = onRefresh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            weekSection
                .padding(.horizontal, 16)

            if viewModel.tasks.isEmpty, viewModel.isLoading {
                ProgressView(AppLocalized.string(L10n.Schedule.loadingTasks, locale: locale))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else if viewModel.tasks.isEmpty, let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label(AppLocalized.string(L10n.Common.loading, locale: locale), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(AppLocalized.string(L10n.Common.reload, locale: locale)) {
                        Task {
                            await refreshTasks()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .top) {
                    dayScheduleContent
                        .id(selectedDay)
                        .transition(dayContentTransition)
                }
                .animation(daySwipeSpring, value: selectedDay)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(x: interactiveDayDragOffset)
                .clipped()
                .simultaneousGesture(dayChangeDragGesture)
            }
        }
        .background(AppTheme.ColorToken.background.ignoresSafeArea())
        .onChange(of: selectedDate) { oldValue, newValue in
            updateDaySlideDirection(from: oldValue, to: newValue)
            let normalized = dayID(for: newValue)
            let targetWeekPage = weekOffsetForDate(normalized)
            if weekOffset != targetWeekPage {
                withAnimation(.easeInOut(duration: 0.25)) {
                    weekOffset = targetWeekPage
                }
            }
        }
    }

    private var dayScheduleContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if allDayTasks.isEmpty == false {
                allDayTasksPinnedStrip
            }
            timelineSection
        }
    }

    private var dayContentTransition: AnyTransition {
        let removalEdge: Edge = daySlideInsertionEdge == .trailing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: daySlideInsertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
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
            let forward = loopDay > selectedDay
            applySelectedDate(loopDay, insertionEdge: forward ? .trailing : .leading)
        } label: {
            VStack(spacing: 4) {
                Text(loopDate.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(selected ? AppTheme.ColorToken.accent : .secondary)
                Text(String(Calendar.current.component(.day, from: loopDate)))
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

    /// 日视图时间轴：有任务时内容高度随任务自然撑开；勿对内容层加 `minHeight`，否则会在周条与首条任务之间出现大块空白。
    private var timelineSection: some View {
        Group {
            if viewModel.isLoading {
                pullToRefreshScrollContainer(minHeight: 360) {
                    ProgressView(AppLocalized.string(L10n.Schedule.loadingTasks, locale: locale))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
            } else if let errorMessage = viewModel.errorMessage {
                pullToRefreshScrollContainer(minHeight: 360) {
                    ContentUnavailableView {
                        Label(AppLocalized.string(L10n.Common.loading, locale: locale), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button(AppLocalized.string(L10n.Common.reload, locale: locale)) {
                            Task {
                                await refreshTasks()
                            }
                        }
                    }
                }
            } else {
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                if timedTasks.isEmpty == false {
                                    ScheduleTaskAnchorFlow(
                                        timedTasks: timedTasks,
                                        selectedCalendarDay: selectedDay,
                                        compactGapHeight: taskFlowCompactGapHeight,
                                        longIdleThreshold: taskFlowLongIdleThreshold,
                                        taskAnchor: { taskDisplayDate($0) },
                                        taskEnd: { taskEndDate($0) },
                                        forWhomAvatars: { viewModel.forWhomAvatarSources(for: $0) },
                                        assigneeLabel: { assigneeLabel(for: $0) },
                                        displayTitle: { viewModel.displayTitle(for: $0) },
                                        onTaskTap: { onTaskSelect($0) }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                        .refreshable {
                            await refreshTasks()
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

    private var dayChangeDragGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                let horizontalTranslation = value.translation.width
                let verticalTranslation = value.translation.height
                guard abs(horizontalTranslation) > abs(verticalTranslation) else { return }
                let damped = horizontalTranslation * 0.55
                interactiveDayDragOffset = max(-dayDragMaxOffset, min(dayDragMaxOffset, damped))
            }
            .onEnded { value in
                let horizontalTranslation = value.translation.width
                let verticalTranslation = value.translation.height
                guard abs(horizontalTranslation) > abs(verticalTranslation) else {
                    resetInteractiveDayDrag()
                    return
                }
                let predicted = value.predictedEndTranslation.width
                let effective = abs(predicted) > abs(horizontalTranslation) ? predicted : horizontalTranslation
                if effective > 50 {
                    goToPreviousDay()
                } else if effective < -50 {
                    goToNextDay()
                } else {
                    resetInteractiveDayDrag()
                }
            }
    }

    private func resetInteractiveDayDrag() {
        withAnimation(daySwipeSpring) {
            interactiveDayDragOffset = 0
        }
    }

    private func goToPreviousDay() {
        let calendar = Calendar.current
        guard let newDate = calendar.date(byAdding: .day, value: -1, to: selectedDay) else { return }
        applySelectedDate(calendar.startOfDay(for: newDate), insertionEdge: .leading)
    }

    private func goToNextDay() {
        let calendar = Calendar.current
        guard let newDate = calendar.date(byAdding: .day, value: 1, to: selectedDay) else { return }
        applySelectedDate(calendar.startOfDay(for: newDate), insertionEdge: .trailing)
    }

    private func applySelectedDate(_ day: Date, insertionEdge: Edge) {
        let normalized = dayID(for: day)
        guard normalized != selectedDay else {
            resetInteractiveDayDrag()
            return
        }
        daySlideInsertionEdge = insertionEdge
        withAnimation(daySwipeSpring) {
            interactiveDayDragOffset = 0
            selectedDate = normalized
        }
    }

    private func updateDaySlideDirection(from oldValue: Date, to newValue: Date) {
        let oldDay = dayID(for: oldValue)
        let newDay = dayID(for: newValue)
        guard oldDay != newDay else { return }
        daySlideInsertionEdge = newDay > oldDay ? .trailing : .leading
    }

    private func pullToRefreshScrollContainer<Content: View>(
        minHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .refreshable {
            await refreshTasks()
        }
    }

    private func refreshTasks() async {
        if let onRefresh {
            await onRefresh()
        } else {
            await viewModel.loadTasks()
        }
    }

    /// 周历下方置顶：`is_all_day` 任务专用紧凑卡片（标题 + 为了谁），横向滑动。
    /// 左侧「全天」与时间列同宽左对齐；卡片宽度与锚点行右侧任务卡一致（随 ScrollView 可视宽度）。
    private var allDayTasksPinnedStrip: some View {
        HStack(alignment: .top, spacing: ScheduleTimelineMetrics.rowSpacing) {
            Text(L10n.Common.allDay.localized)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: ScheduleTimelineMetrics.timeColumnWidth, alignment: .trailing)
                .padding(.top, 2)

            Color.clear
                .frame(width: ScheduleTimelineMetrics.axisColumnWidth)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allDayTasks) { task in
                        AllDayTaskRowView(
                            task: task,
                            displayTitle: viewModel.displayTitle(for: task),
                            forWhomAvatars: viewModel.forWhomAvatarSources(for: task)
                        )
                        .frame(width: resolvedAllDayCardWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTaskSelect(task)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                if abs(width - allDayCardSlotWidth) > 0.5 {
                    allDayCardSlotWidth = width
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func taskEndDate(_ task: FamilyTask) -> Date {
        task.timelineEndDate
    }

    private func scrollTaskAnchorFlowToInitial(proxy: ScrollViewProxy, animated: Bool = true) {
        guard timedTasks.isEmpty == false else { return }
        let cal = Calendar.current
        let viewingToday = cal.isDateInToday(selectedDay)
        let sorted = ScheduleTimelineMetrics.sortedForTimeline(timedTasks, anchor: taskDisplayDate)
        guard let first = sorted.first else { return }
        let firstID = "task-\(first.id.uuidString)"

        let action = {
            if viewingToday {
                proxy.scrollTo(ScheduleAnchorFlowScrollIDs.nowMarker, anchor: .top)
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
                Text(L10n.Schedule.noTasksScheduledToday.localized)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text(L10n.Common.enjoyYourTimeTogetherOrPlanSomethingNew.localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                actionChip(emoji: "✨", title: L10n.Common.dinnerTogether, dueDateKind: .selectedDay)
                actionChip(emoji: "🛒", title: L10n.Common.groceryList, dueDateKind: .dayAfterSelected)
                actionChip(emoji: "🧸", title: L10n.Common.kidsActivity, dueDateKind: .nextSaturdayFromSelected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -50)
    }

    /// Emoji 与标题样式隔离，避免环境里的 `.foregroundStyle` 把 Emoji 压成单色。
    private func actionChip(emoji: String, title: L10n.Entry, dueDateKind: QuickCreateDueDateKind = .selectedDay) -> some View {
        Button {
            onQuickCreate(AppLocalized.string(title, locale: locale), defaultDueDate(for: dueDateKind))
        } label: {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 22))
                    .fixedSize()
                Text(title.localized)
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

    private var selectedDateTasks: [FamilyTask] {
        viewModel.scheduledTasks
            .filter { task in
                Calendar.current.isDate(taskDisplayDate(task), inSameDayAs: selectedDate)
            }
            .sorted { lhs, rhs in
                ScheduleTimelineMetrics.timelineSortsBefore(lhs, rhs, anchor: taskDisplayDate)
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

    private var selectedDay: Date {
        dayID(for: selectedDate)
    }

    private func taskCount(for date: Date) -> Int {
        viewModel.scheduledTasks.reduce(into: 0) { result, task in
            if Calendar.current.isDate(taskDisplayDate(task), inSameDayAs: date) {
                result += 1
            }
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

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
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


#Preview("Day mode") {
    TaskModeDayView(
        selectedDate: .constant(Date()),
        viewModel: AppViewModels.makeScheduleViewModel(),
        onTaskSelect: { _ in },
        onQuickCreate: { _, _ in }
    )
}
