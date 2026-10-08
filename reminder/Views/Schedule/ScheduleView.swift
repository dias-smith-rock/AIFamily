import SwiftUI
import Kingfisher

/// Day 模式：周历条 + 全天条 + 锚点时间轴（由 `TaskListView` 嵌入）。
struct TaskModeDayView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appSettings: AppSettingsManager

    private let taskFlowCompactGapHeight: CGFloat = ScheduleTimelineMetrics.taskFlowGapHeight
    private let taskFlowLongIdleThreshold: TimeInterval = 3600
    /// 未收到 ScrollView 宽度前占位，避免首张卡片过窄（约等于常见屏宽减去左右边距与时间列）。
    private let allDayCardFallbackWidth: CGFloat = 300

    private var displayCalendar: Calendar { appSettings.effectiveCalendar }

    private var resolvedAllDayCardWidth: CGFloat {
        allDayCardSlotWidth > 8 ? allDayCardSlotWidth : allDayCardFallbackWidth
    }

    /// 固定锚点：用于把三页窗口映射成真实自然周（与 `weekOffset` 搭配使用）。
    @State private var weekEpochStart: Date = TaskModeDayView.startOfWeek(for: Date())
    /// 相对 `weekEpochStart` 的周偏移。
    @State private var weekOffset: Int = 0
    /// 三页窗口：0 上一周 / 1 当前周 / 2 下一周。
    @State private var pagerSlot: Int = ScheduleWeekCalendar.pagerCenterSlot

    @ObservedObject var viewModel: ScheduleViewModel
    @Binding var selectedDate: Date

    /// 横向全天列表可视区域宽度，用于单卡宽度与下方 `TaskCardView` 一致。
    @State private var allDayCardSlotWidth: CGFloat = 0
    @State private var daySlideInsertionEdge: Edge = .trailing
    @State private var interactiveDayDragOffset: CGFloat = 0
    /// 横向切日滑动进行中时抑制按钮点击，避免“滑完误触”。
    @State private var isDaySwipeGestureActive = false

    private let daySwipeSpring = Animation.spring(response: 0.34, dampingFraction: 0.88)
    private let dayDragMaxOffset: CGFloat = 96
    private let daySwipeSuppressTapClearDelayNanoseconds: UInt64 = 80_000_000

    let onTaskSelect: (FamilyTask) -> Void
    let onQuickCreate: (String, Date?) -> Void
    let onInviteFamily: (() -> Void)?
    let onRefresh: (() async -> Void)?

    init(
        selectedDate: Binding<Date>,
        viewModel: ScheduleViewModel,
        onTaskSelect: @escaping (FamilyTask) -> Void,
        onQuickCreate: @escaping (String, Date?) -> Void,
        onInviteFamily: (() -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil
    ) {
        self._selectedDate = selectedDate
        self.viewModel = viewModel
        self.onTaskSelect = onTaskSelect
        self.onQuickCreate = onQuickCreate
        self.onInviteFamily = onInviteFamily
        self.onRefresh = onRefresh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 独立子视图 + Equatable：切日拖动只更新 offset 时跳过周条重建。
            TaskModeDayWeekStripPager(
                weekEpochStart: $weekEpochStart,
                weekOffset: $weekOffset,
                pagerSlot: $pagerSlot,
                selectedDay: selectedDay,
                scheduledTasks: viewModel.scheduledTasks,
                displayCalendar: displayCalendar,
                locale: locale,
                onSelectDay: { day in
                    let forward = day > selectedDay
                    applySelectedDate(day, insertionEdge: forward ? .trailing : .leading)
                }
            )
            .equatable()

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
                dayContentHost
            }
        }
        .background(AppTheme.ColorToken.background.ignoresSafeArea())
        .onAppear {
            weekOffset = weekOffsetForDate(selectedDate)
            pagerSlot = ScheduleWeekCalendar.pagerCenterSlot
        }
        .onChange(of: selectedDate) { oldValue, newValue in
            updateDaySlideDirection(from: oldValue, to: newValue)
            let normalized = dayID(for: newValue)
            let targetWeekPage = weekOffsetForDate(normalized)
            if weekOffset != targetWeekPage {
                withAnimation(.easeInOut(duration: 0.25)) {
                    weekOffset = targetWeekPage
                    pagerSlot = ScheduleWeekCalendar.pagerCenterSlot
                }
            }
        }
        .onChange(of: pagerSlot) { oldSlot, newSlot in
            handleWeekPagerSlotChange(from: oldSlot, to: newSlot)
        }
    }

    private var dayContentHost: some View {
        ZStack(alignment: .top) {
            TaskModeDaySchedulePane(
                selectedDay: selectedDay,
                selectedDate: $selectedDate,
                dayTasks: selectedDateTasks,
                isLoading: viewModel.isLoading,
                errorMessage: viewModel.errorMessage,
                allDayCardSlotWidth: $allDayCardSlotWidth,
                resolvedAllDayCardWidth: resolvedAllDayCardWidth,
                locale: locale,
                displayCalendar: displayCalendar,
                taskFlowCompactGapHeight: taskFlowCompactGapHeight,
                taskFlowLongIdleThreshold: taskFlowLongIdleThreshold,
                viewModel: viewModel,
                onTaskSelect: onTaskSelect,
                onQuickCreate: onQuickCreate,
                onInviteFamily: onInviteFamily,
                onRefresh: onRefresh,
                isDaySwipeGestureActive: isDaySwipeGestureActive
            )
            .id(selectedDay)
            .transition(dayContentTransition)
        }
        .animation(daySwipeSpring, value: selectedDay)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(x: interactiveDayDragOffset)
        .clipped()
        .simultaneousGesture(dayChangeDragGesture)
    }

    private var dayContentTransition: AnyTransition {
        let removalEdge: Edge = daySlideInsertionEdge == .trailing ? .leading : .trailing
        // 仅位移、不加 opacity，避免切日时整页时间轴做半透明合成。
        return .asymmetric(
            insertion: .move(edge: daySlideInsertionEdge),
            removal: .move(edge: removalEdge)
        )
    }

    /// `date` 所在自然周相对 `weekEpochStart` 是第几周。
    private func weekOffsetForDate(_ date: Date) -> Int {
        ScheduleWeekCalendar.weekOffset(
            for: dayID(for: date),
            epochStart: weekEpochStart,
            calendar: displayCalendar
        )
    }

    private func handleWeekPagerSlotChange(from oldSlot: Int, to newSlot: Int) {
        guard oldSlot != newSlot else { return }
        switch newSlot {
        case 0:
            weekOffset -= 1
            normalizeWeekEpochIfNeeded()
            recenterWeekPagerSlot()
        case 2:
            weekOffset += 1
            normalizeWeekEpochIfNeeded()
            recenterWeekPagerSlot()
        default:
            break
        }
    }

    private func recenterWeekPagerSlot() {
        guard pagerSlot != ScheduleWeekCalendar.pagerCenterSlot else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pagerSlot = ScheduleWeekCalendar.pagerCenterSlot
        }
    }

    private func normalizeWeekEpochIfNeeded() {
        guard abs(weekOffset) > 52 else { return }
        weekEpochStart = ScheduleWeekCalendar.weekStart(
            forOffset: weekOffset,
            epochStart: weekEpochStart,
            calendar: displayCalendar
        )
        weekOffset = 0
    }

    private static func startOfWeek(for date: Date, calendar cal: Calendar = AppDisplayTimeZone.calendar()) -> Date {
        ScheduleWeekCalendar.startOfWeek(for: date, calendar: cal)
    }

    private var dayChangeDragGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                let horizontalTranslation = value.translation.width
                let verticalTranslation = value.translation.height
                guard abs(horizontalTranslation) > abs(verticalTranslation) else { return }
                if isDaySwipeGestureActive == false {
                    isDaySwipeGestureActive = true
                }
                let damped = horizontalTranslation * 0.55
                interactiveDayDragOffset = max(-dayDragMaxOffset, min(dayDragMaxOffset, damped))
            }
            .onEnded { value in
                defer { scheduleClearDaySwipeTapSuppression() }
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

    private func scheduleClearDaySwipeTapSuppression() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: daySwipeSuppressTapClearDelayNanoseconds)
            isDaySwipeGestureActive = false
        }
    }

    private func performControlActionUnlessDaySwiping(_ action: () -> Void) {
        guard isDaySwipeGestureActive == false else { return }
        action()
    }

    private func resetInteractiveDayDrag() {
        withAnimation(daySwipeSpring) {
            interactiveDayDragOffset = 0
        }
    }

    private func goToPreviousDay() {
        let calendar = displayCalendar
        guard let newDate = calendar.date(byAdding: .day, value: -1, to: selectedDay) else { return }
        applySelectedDate(calendar.startOfDay(for: newDate), insertionEdge: .leading)
    }

    private func goToNextDay() {
        let calendar = displayCalendar
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
    private func allDayTasksPinnedStrip(tasks: [FamilyTask]) -> some View {
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
                    ForEach(tasks) { task in
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

    private func scrollTaskAnchorFlowToInitial(
        proxy: ScrollViewProxy,
        timedTasks: [FamilyTask],
        animated: Bool = true
    ) {
        guard timedTasks.isEmpty == false else { return }
        let cal = displayCalendar
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

    private var showsSoloHouseholdInviteCTA: Bool {
        let activeHumans = viewModel.householdMembers.filter { $0.isActiveMembership() }.count
        return activeHumans <= 1
    }

    @ViewBuilder
    private func emptyStateView() -> some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.13))
                        .frame(width: 88, height: 88)
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.orange)
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(.top, 8)

                VStack(spacing: 8) {
                    Text(L10n.Schedule.emptyFamilyReadyTitle.localized)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Text(L10n.Schedule.emptyFamilyReadySubtitle.localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let onInviteFamily {
                    Button {
                        performControlActionUnlessDaySwiping {
                            AnalyticsManager.logEmptyStateCTATapped(
                                surface: AnalyticsManager.EmptyStateSurface.schedule,
                                cta: AnalyticsManager.EmptyStateCTA.invite
                            )
                            onInviteFamily()
                        }
                    } label: {
                        Label {
                            Text(L10n.Schedule.emptyInvitePartner.localized)
                                .font(.body.weight(.semibold))
                        } icon: {
                            Image(systemName: "person.badge.plus")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, showsSoloHouseholdInviteCTA ? 4 : 0)
                }

                Button {
                    performControlActionUnlessDaySwiping {
                        AnalyticsManager.logEmptyStateCTATapped(
                            surface: AnalyticsManager.EmptyStateSurface.schedule,
                            cta: AnalyticsManager.EmptyStateCTA.create
                        )
                        onQuickCreate("", defaultDueDate(for: .selectedDay))
                    }
                } label: {
                    Label {
                        Text(L10n.Schedule.emptyNewTask.localized)
                            .font(.body.weight(.semibold))
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.primary)
                    .background(AppTheme.ColorToken.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                VStack(spacing: 12) {
                    Text(L10n.Schedule.emptyQuickAddSection.localized)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 10) {
                        actionChip(emoji: "✨", title: L10n.Common.dinnerTogether, dueDateKind: .selectedDay)
                        actionChip(emoji: "🛒", title: L10n.Common.groceryList, dueDateKind: .dayAfterSelected)
                        actionChip(emoji: "🧸", title: L10n.Common.kidsActivity, dueDateKind: .nextSaturdayFromSelected)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Emoji 与标题样式隔离，避免环境里的 `.foregroundStyle` 把 Emoji 压成单色。
    private func actionChip(emoji: String, title: L10n.Entry, dueDateKind: QuickCreateDueDateKind = .selectedDay) -> some View {
        Button {
            performControlActionUnlessDaySwiping {
                AnalyticsManager.logEmptyStateCTATapped(
                    surface: AnalyticsManager.EmptyStateSurface.schedule,
                    cta: AnalyticsManager.EmptyStateCTA.create
                )
                onQuickCreate(AppLocalized.string(title, locale: locale), defaultDueDate(for: dueDateKind))
            }
        } label: {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 18))
                    .fixedSize()
                Text(title.localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.ColorToken.surfaceMuted)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var selectedDateTasks: [FamilyTask] {
        let day = selectedDay
        let cal = displayCalendar
        return viewModel.scheduledTasks
            .filter { task in
                task.scheduleDisplayDay(displayCalendar: cal) == day
            }
            .sorted { lhs, rhs in
                ScheduleTimelineMetrics.timelineSortsBefore(lhs, rhs, anchor: taskDisplayDate)
            }
    }

    private func dayID(for date: Date) -> Date {
        displayCalendar.startOfDay(for: date)
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
        let cal = displayCalendar
        let base = dayID(for: anchor)
        guard let shifted = cal.date(byAdding: .day, value: days, to: base) else { return base }
        return cal.startOfDay(for: shifted)
    }

    /// `weekday` 与 `Calendar.Component.weekday` 一致（如美国历：1=周日 … 7=周六）。
    private func nextSaturdayOnOrAfter(_ anchor: Date) -> Date {
        let cal = displayCalendar
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

    private func taskDisplayDate(_ task: FamilyTask) -> Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private func assigneeLabel(for task: FamilyTask) -> String {
        viewModel.assigneeLabel(for: task, locale: locale)
    }
}

// MARK: - Day week strip (3-page window)

/// 日视图顶部周条：仅挂载上一周 / 当前周 / 下一周，侧滑后重定中心页。
private struct TaskModeDayWeekStripPager: View, Equatable {
    @Binding var weekEpochStart: Date
    @Binding var weekOffset: Int
    @Binding var pagerSlot: Int

    let selectedDay: Date
    let scheduledTasks: [FamilyTask]
    let displayCalendar: Calendar
    let locale: Locale
    let onSelectDay: (Date) -> Void

    static func == (lhs: TaskModeDayWeekStripPager, rhs: TaskModeDayWeekStripPager) -> Bool {
        lhs.weekEpochStart == rhs.weekEpochStart
            && lhs.weekOffset == rhs.weekOffset
            && lhs.pagerSlot == rhs.pagerSlot
            && lhs.selectedDay == rhs.selectedDay
            && lhs.scheduledTasks.map(\.id) == rhs.scheduledTasks.map(\.id)
            && lhs.locale.identifier == rhs.locale.identifier
    }

    var body: some View {
        let taskCounts = taskCountsByDay()
        return ScheduleWeekDayStripChrome {
            TabView(selection: $pagerSlot) {
                weekStrip(for: weekOffset - 1, taskCounts: taskCounts)
                    .tag(0)
                weekStrip(for: weekOffset, taskCounts: taskCounts)
                    .tag(ScheduleWeekCalendar.pagerCenterSlot)
                weekStrip(for: weekOffset + 1, taskCounts: taskCounts)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .equatable()
    }

    private func weekStrip(for offset: Int, taskCounts: [Date: Int]) -> some View {
        let days = ScheduleWeekCalendar.daysInWeek(
            weekOffset: offset,
            epochStart: weekEpochStart,
            calendar: displayCalendar
        )
        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { loopDate in
                let loopDay = displayCalendar.startOfDay(for: loopDate)
                ScheduleWeekDayStripCell(
                    date: loopDate,
                    isSelected: loopDay == selectedDay,
                    taskCount: taskCounts[loopDay, default: 0],
                    locale: locale,
                    calendar: displayCalendar
                ) {
                    onSelectDay(loopDay)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 仅扫描可见三周范围内的任务，单次遍历生成日计数。
    private func taskCountsByDay() -> [Date: Int] {
        let offsets = [weekOffset - 1, weekOffset, weekOffset + 1]
        var minDay: Date?
        var maxDay: Date?
        for offset in offsets {
            let days = ScheduleWeekCalendar.daysInWeek(
                weekOffset: offset,
                epochStart: weekEpochStart,
                calendar: displayCalendar
            )
            guard let first = days.first, let last = days.last else { continue }
            let start = displayCalendar.startOfDay(for: first)
            let end = displayCalendar.startOfDay(for: last)
            if minDay == nil || start < minDay! {
                minDay = start
            }
            if maxDay == nil || end > maxDay! {
                maxDay = end
            }
        }
        guard let minDay, let maxDay else { return [:] }

        var result: [Date: Int] = [:]
        for task in scheduledTasks {
            let day = task.scheduleDisplayDay(displayCalendar: displayCalendar)
            guard day >= minDay, day <= maxDay else { continue }
            result[day, default: 0] += 1
        }
        return result
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
        onQuickCreate: { _, _ in },
        onInviteFamily: {}
    )
}

/// 简易横向换行布局，用于空态快捷 chip。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            height = max(height, y + rowHeight)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
