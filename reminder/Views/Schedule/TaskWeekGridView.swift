import SwiftUI

private struct WeekPageBundle {
    let offset: Int
    let days: [Date]
    let tasks: [FamilyTask]
}

/// Week 模式：按日纵向议程 + 多列可读任务卡（由 `TaskListView` 嵌入）。
struct TaskWeekGridView: View {
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appSettings: AppSettingsManager

    @ObservedObject var viewModel: ScheduleViewModel
    @Binding var selectedDate: Date

    private var displayCalendar: Calendar { appSettings.effectiveCalendar }

    let onTaskSelect: (FamilyTask) -> Void
    var onTaskComplete: ((FamilyTask) -> Void)? = nil
    var onTaskDelete: ((FamilyTask) -> Void)? = nil
    let onRefresh: (() async -> Void)?
    @Binding var showsBackToCurrentWeekButton: Bool
    @Binding var backToCurrentWeekTrigger: Int

    @State private var weekEpochStart: Date = ScheduleWeekCalendar.startOfWeek(for: Date())
    @State private var weekOffset: Int = 0
    /// 三页窗口：0 上一周 / 1 当前周 / 2 下一周。
    @State private var pagerSlot: Int = ScheduleWeekCalendar.pagerCenterSlot
    /// 程序化回中中：忽略 TabView selection 回写触发的 `onChange`，避免双驱动打架。
    @State private var isRecenteringPager = false
    @State private var pagerRecenterTask: Task<Void, Never>?
    /// 首帧后再挂载上一周 / 下一周页。
    @State private var isAdjacentWeekPagesReady = false
    @State private var firstPaintExpansionTask: Task<Void, Never>?
    @State private var divisionAvoidanceInsets = EdgeInsets()

    private let horizontalPadding: CGFloat = 16

    init(
        selectedDate: Binding<Date>,
        viewModel: ScheduleViewModel,
        onTaskSelect: @escaping (FamilyTask) -> Void,
        onTaskComplete: ((FamilyTask) -> Void)? = nil,
        onTaskDelete: ((FamilyTask) -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil,
        showsBackToCurrentWeekButton: Binding<Bool> = .constant(false),
        backToCurrentWeekTrigger: Binding<Int> = .constant(0)
    ) {
        self._selectedDate = selectedDate
        self.viewModel = viewModel
        self.onTaskSelect = onTaskSelect
        self.onTaskComplete = onTaskComplete
        self.onTaskDelete = onTaskDelete
        self.onRefresh = onRefresh
        self._showsBackToCurrentWeekButton = showsBackToCurrentWeekButton
        self._backToCurrentWeekTrigger = backToCurrentWeekTrigger
    }

    var body: some View {
        Group {
            if let errorMessage = viewModel.errorMessage, viewModel.tasks.isEmpty {
                ContentUnavailableView {
                    Label(AppLocalized.string(L10n.Common.loading, locale: locale), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(AppLocalized.string(L10n.Common.reload, locale: locale)) {
                        Task { await refreshTasks() }
                    }
                }
            } else {
                weekPager
            }
        }
        .schedulePageBackground()
        .duoCanvasChromePadding(extra: divisionAvoidanceInsets)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        updateDivisionInsets(from: geo)
                    }
                    .onChange(of: geo.size) { oldSize, newSize in
                        guard abs(oldSize.width - newSize.width) > 1
                            || abs(oldSize.height - newSize.height) > 1 else { return }
                        updateDivisionInsets(from: geo)
                    }
            }
        }
        .onAppear {
            WeekViewPerformanceTracer.mark(
                "taskWeekGridView.onAppear",
                note: "scheduledTaskCount=\(viewModel.scheduledTasks.count)"
            )
            WeekViewPerformanceTracer.notePendingWeekOffsetChange(source: "initialAppearSync")
            weekOffset = ScheduleWeekCalendar.weekOffset(
                for: selectedDate,
                epochStart: weekEpochStart
            )
            pagerSlot = ScheduleWeekCalendar.pagerCenterSlot
            scheduleFirstPaintExpansion()
            syncBackToCurrentWeekButtonVisibility()
        }
        .onDisappear {
            firstPaintExpansionTask?.cancel()
            firstPaintExpansionTask = nil
            pagerRecenterTask?.cancel()
            pagerRecenterTask = nil
            isRecenteringPager = false
            showsBackToCurrentWeekButton = false
        }
        .onChange(of: weekOffset) { oldOffset, newOffset in
            WeekViewPerformanceTracer.recordWeekOffsetChange(from: oldOffset, to: newOffset)
            syncBackToCurrentWeekButtonVisibility()
        }
        .onChange(of: pagerSlot) { oldSlot, newSlot in
            handlePagerSlotChange(from: oldSlot, to: newSlot)
        }
        .onChange(of: selectedDate) { _, newValue in
            let target = ScheduleWeekCalendar.weekOffset(
                for: newValue,
                epochStart: weekEpochStart
            )
            if weekOffset != target {
                WeekViewPerformanceTracer.notePendingWeekOffsetChange(source: "selectedDateSync")
                applyWeekOffset(target, animated: true)
            }
        }
        .onChange(of: backToCurrentWeekTrigger) { oldValue, newValue in
            guard newValue != oldValue else { return }
            jumpToCurrentWeek()
        }
    }

    private func updateDivisionInsets(from geo: GeometryProxy) {
        let next = geo.duoLayoutMetrics(
            horizontalSizeClass: horizontalSizeClass
        ).divisionAvoidanceInsets
        guard divisionAvoidanceInsets != next else { return }
        divisionAvoidanceInsets = next
    }

    // MARK: - Week pager

    private var weekPager: some View {
        let currentBundle = weekPageBundle(offset: weekOffset)
        let previousBundle = isAdjacentWeekPagesReady
            ? weekPageBundle(offset: weekOffset - 1)
            : nil
        let nextBundle = isAdjacentWeekPagesReady
            ? weekPageBundle(offset: weekOffset + 1)
            : nil

        return TabView(selection: $pagerSlot) {
            if let previousBundle {
                weekPage(bundle: previousBundle, slot: 0)
            } else {
                weekPagerPlaceholderPage(slot: 0)
            }

            weekPage(bundle: currentBundle, slot: ScheduleWeekCalendar.pagerCenterSlot)

            if let nextBundle {
                weekPage(bundle: nextBundle, slot: 2)
            } else {
                weekPagerPlaceholderPage(slot: 2)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(isAdjacentWeekPagesReady && isRecenteringPager == false)
        .onAppear {
            WeekViewPerformanceTracer.mark("weekPager.onAppear")
            scheduleFirstPaintExpansion()
        }
    }

    private func weekPagerPlaceholderPage(slot: Int) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tag(slot)
    }

    private func weekPage(bundle: WeekPageBundle, slot: Int) -> some View {
        let days = bundle.days
        let weekTasks = bundle.tasks
        let offset = bundle.offset

        return WeekAgendaScrollArea(
            days: days,
            weekTasks: weekTasks,
            selectedDate: $selectedDate,
            calendar: displayCalendar,
            locale: locale,
            horizontalPadding: horizontalPadding,
            viewModel: viewModel,
            onTaskSelect: onTaskSelect,
            onTaskComplete: onTaskComplete,
            onTaskDelete: onTaskDelete,
            onRefresh: refreshTasks
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: isDisplayingCurrentWeek(offset: offset))
        .tag(slot)
        .id(offset)
        .onAppear {
            WeekViewPerformanceTracer.recordWeekBodyAppear(offset: offset)
        }
    }

    // MARK: - First paint expansion

    private func scheduleFirstPaintExpansion() {
        guard isAdjacentWeekPagesReady == false else { return }
        firstPaintExpansionTask?.cancel()
        firstPaintExpansionTask = Task { @MainActor in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            expandFirstPaintContent()
        }
    }

    private func ensureFirstPaintExpanded() {
        guard isAdjacentWeekPagesReady == false else { return }
        firstPaintExpansionTask?.cancel()
        firstPaintExpansionTask = nil
        expandFirstPaintContent()
    }

    private func expandFirstPaintContent() {
        guard isAdjacentWeekPagesReady == false else { return }
        WeekViewPerformanceTracer.mark(
            "firstPaint.expand",
            note: "enablingAdjacentAgendaPages"
        )
        isAdjacentWeekPagesReady = true
    }

    // MARK: - Pager navigation

    private func weekPageBundle(offset: Int) -> WeekPageBundle {
        let days = ScheduleWeekCalendar.daysInWeek(
            weekOffset: offset,
            epochStart: weekEpochStart
        )
        return WeekPageBundle(
            offset: offset,
            days: days,
            tasks: filteredTasks(for: days)
        )
    }

    private func handlePagerSlotChange(from oldSlot: Int, to newSlot: Int) {
        guard isRecenteringPager == false else { return }
        guard oldSlot != newSlot else { return }
        ensureFirstPaintExpanded()

        let weekDelta: Int
        switch newSlot {
        case 0:
            weekDelta = -1
        case 2:
            weekDelta = 1
        default:
            return
        }

        WeekViewPerformanceTracer.notePendingWeekOffsetChange(source: "tabViewSwipe")
        commitWeekSwipe(delta: weekDelta)
    }

    private func shiftDisplayedWeek(by weeks: Int) {
        weekOffset += weeks
        normalizeEpochIfNeeded()
        let calendar = Calendar.current
        if let shiftedDate = calendar.date(byAdding: .day, value: weeks * 7, to: selectedDate) {
            selectedDate = calendar.startOfDay(for: shiftedDate)
        }
    }

    private func commitWeekSwipe(delta: Int) {
        isRecenteringPager = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            shiftDisplayedWeek(by: delta)
            pagerSlot = ScheduleWeekCalendar.pagerCenterSlot
        }
        scheduleClearPagerRecenterFlag()
    }

    private func applyWeekOffset(_ target: Int, animated: Bool) {
        ensureFirstPaintExpanded()
        let updates = {
            weekOffset = target
            pagerSlot = ScheduleWeekCalendar.pagerCenterSlot
        }
        isRecenteringPager = true
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                updates()
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                updates()
            }
        }
        scheduleClearPagerRecenterFlag()
    }

    private func scheduleClearPagerRecenterFlag() {
        pagerRecenterTask?.cancel()
        pagerRecenterTask = Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard Task.isCancelled == false else { return }
            isRecenteringPager = false
        }
    }

    private func normalizeEpochIfNeeded() {
        guard abs(weekOffset) > 52 else { return }
        let rebasedStart = ScheduleWeekCalendar.weekStart(
            forOffset: weekOffset,
            epochStart: weekEpochStart
        )
        weekEpochStart = rebasedStart
        weekOffset = 0
    }

    // MARK: - Back to current week

    private func syncBackToCurrentWeekButtonVisibility() {
        let shouldShow = isDisplayingCurrentWeek(offset: weekOffset) == false
        if showsBackToCurrentWeekButton != shouldShow {
            showsBackToCurrentWeekButton = shouldShow
        }
    }

    private func isDisplayingCurrentWeek(offset: Int) -> Bool {
        offset == ScheduleWeekCalendar.weekOffset(for: Date(), epochStart: weekEpochStart)
    }

    private func jumpToCurrentWeek() {
        ensureFirstPaintExpanded()
        let today = displayCalendar.startOfDay(for: Date())
        let targetOffset = ScheduleWeekCalendar.weekOffset(for: today, epochStart: weekEpochStart)
        WeekViewPerformanceTracer.notePendingWeekOffsetChange(source: "jumpToCurrentWeek")
        isRecenteringPager = true
        withAnimation(.easeInOut(duration: 0.25)) {
            weekOffset = targetOffset
            selectedDate = today
            pagerSlot = ScheduleWeekCalendar.pagerCenterSlot
        }
        scheduleClearPagerRecenterFlag()
    }

    // MARK: - Task filtering

    private func filteredTasks(for days: [Date]) -> [FamilyTask] {
        guard let first = days.first, let last = days.last else { return [] }
        let cal = displayCalendar
        let weekStart = cal.startOfDay(for: first)
        let weekEnd = cal.startOfDay(for: last)
        return WeekViewPerformanceTracer.measureTasksFilter(
            scheduledTaskCount: viewModel.scheduledTasks.count
        ) {
            viewModel.scheduledTasks.filter { task in
                let day = task.scheduleDisplayDay(displayCalendar: cal)
                return day >= weekStart && day <= weekEnd
            }
        }
    }

    private func refreshTasks() async {
        if let onRefresh {
            await onRefresh()
        } else {
            await LocalFirstSyncCoordinator.syncNow(reason: "pullToRefreshScheduleWeek")
            await viewModel.loadTasks(silent: true)
        }
    }
}

// MARK: - Agenda scroll

private enum WeekAgendaMetrics {
    static let dayCount = 7
    static let dateColumnWidth: CGFloat = 44
    static let cardWidth: CGFloat = 132
    static let cardSpacing: CGFloat = 8
    static let dividerHeight: CGFloat = 0.5
    /// 卡片相对日行内边距（上下合计），避免贴死分割线。
    static let cardVerticalInset: CGFloat = 12
}

private struct WeekAgendaScrollArea: View {
    let days: [Date]
    let weekTasks: [FamilyTask]
    @Binding var selectedDate: Date
    let calendar: Calendar
    let locale: Locale
    let horizontalPadding: CGFloat
    @ObservedObject var viewModel: ScheduleViewModel
    let onTaskSelect: (FamilyTask) -> Void
    var onTaskComplete: ((FamilyTask) -> Void)? = nil
    var onTaskDelete: ((FamilyTask) -> Void)? = nil
    let onRefresh: () async -> Void

    var body: some View {
        GeometryReader { geometry in
            let metrics = rowMetrics(for: geometry.size.height)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(days.prefix(WeekAgendaMetrics.dayCount).enumerated()), id: \.element) { index, day in
                    WeekAgendaDayRow(
                        day: day,
                        tasks: tasks(for: day),
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(day),
                        calendar: calendar,
                        locale: locale,
                        leadingInset: horizontalPadding,
                        cardHeight: metrics.cardHeight,
                        viewModel: viewModel,
                        onSelectDay: {
                            selectedDate = calendar.startOfDay(for: day)
                        },
                        onTaskSelect: onTaskSelect,
                        onTaskComplete: onTaskComplete,
                        onTaskDelete: onTaskDelete
                    )
                    .frame(height: metrics.dayRowHeight)

                    if index < WeekAgendaMetrics.dayCount - 1 {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: WeekAgendaMetrics.dividerHeight)
                            .padding(.leading, horizontalPadding)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .refreshable {
            await onRefresh()
        }
    }

    /// 7 天 + 6 条分割线均分可用高度，保证一屏内铺满、不纵向滚动。
    private func rowMetrics(for availableHeight: CGFloat) -> (dayRowHeight: CGFloat, cardHeight: CGFloat) {
        let dividerTotal = WeekAgendaMetrics.dividerHeight * CGFloat(WeekAgendaMetrics.dayCount - 1)
        let usable = max(0, availableHeight - dividerTotal)
        let dayRowHeight = usable / CGFloat(WeekAgendaMetrics.dayCount)
        let cardHeight = max(0, dayRowHeight - WeekAgendaMetrics.cardVerticalInset)
        return (dayRowHeight, cardHeight)
    }

    private func tasks(for day: Date) -> [FamilyTask] {
        weekTasks
            .filter {
                calendar.isDate(
                    $0.scheduleDisplayDay(displayCalendar: calendar),
                    inSameDayAs: day
                )
            }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return lhs.isAllDay && rhs.isAllDay == false
                }
                return lhs.scheduleStartDate < rhs.scheduleStartDate
            }
    }
}

// MARK: - Day row

private struct WeekAgendaDayRow: View {
    let day: Date
    let tasks: [FamilyTask]
    let isSelected: Bool
    let isToday: Bool
    let calendar: Calendar
    let locale: Locale
    let leadingInset: CGFloat
    let cardHeight: CGFloat
    @ObservedObject var viewModel: ScheduleViewModel
    let onSelectDay: () -> Void
    let onTaskSelect: (FamilyTask) -> Void
    var onTaskComplete: ((FamilyTask) -> Void)? = nil
    var onTaskDelete: ((FamilyTask) -> Void)? = nil

    @State private var taskStripViewportWidth: CGFloat = 0

    private var dayNumber: Int {
        calendar.component(.day, from: day)
    }

    /// 任务条内容总宽（含尾部 inset）；大于可视宽度时才由卡片横向滚动接手手势。
    private var taskStripContentWidth: CGFloat {
        guard tasks.isEmpty == false else { return 0 }
        let count = CGFloat(tasks.count)
        return count * WeekAgendaMetrics.cardWidth
            + max(0, count - 1) * WeekAgendaMetrics.cardSpacing
            + leadingInset
    }

    private var canScrollTaskStrip: Bool {
        tasks.isEmpty == false && taskStripContentWidth > taskStripViewportWidth + 1
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onSelectDay) {
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(weekdayColor)

                    Text(String(dayNumber))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(dayNumberColor)
                }
                .frame(width: WeekAgendaMetrics.dateColumnWidth, alignment: .center)
            }
            .buttonStyle(.plain)
            .padding(.leading, leadingInset)

            taskStrip
                .frame(maxWidth: .infinity)
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { taskStripViewportWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, newWidth in
                                taskStripViewportWidth = newWidth
                            }
                    }
                }
        }
    }

    @ViewBuilder
    private var taskStrip: some View {
        if canScrollTaskStrip {
            // 内容超出可视宽度：横向 ScrollView 优先响应侧滑，避免被 TabView 换周抢走。
            ScrollView(.horizontal, showsIndicators: false) {
                taskCardsRow
            }
            .scrollBounceBehavior(.basedOnSize)
            .background {
                WeekAgendaNestedScrollGestureBridge()
                    .allowsHitTesting(false)
            }
        } else {
            // 卡片装得下 / 无任务：不装 ScrollView，横向手势交给外层换周。
            taskCardsRow
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var taskCardsRow: some View {
        HStack(alignment: .center, spacing: WeekAgendaMetrics.cardSpacing) {
            ForEach(tasks) { task in
                Button {
                    onTaskSelect(task)
                } label: {
                    WeekTaskEventCard(
                        task: task,
                        title: viewModel.displayTitle(for: task),
                        locale: locale
                    )
                    .frame(
                        width: WeekAgendaMetrics.cardWidth,
                        height: cardHeight
                    )
                }
                .buttonStyle(.plain)
                .taskLongPressContextMenu(
                    showsComplete: task.status != .completed
                        && task.status != .cancelled
                        && onTaskComplete != nil,
                    onEdit: { onTaskSelect(task) },
                    onComplete: { onTaskComplete?(task) },
                    onDelete: { onTaskDelete?(task) }
                )
            }
        }
        .padding(.trailing, leadingInset)
    }

    private var weekdayColor: Color {
        if isToday || isSelected {
            return AppTheme.ColorToken.accent
        }
        return .secondary
    }

    private var dayNumberColor: Color {
        if isToday || isSelected {
            return AppTheme.ColorToken.accent
        }
        return .primary
    }
}

// MARK: - Event card

private struct WeekTaskEventCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let task: FamilyTask
    let title: String
    let locale: Locale

    private var accent: Color {
        task.cardHeaderAccentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.taskCardTitle(for: colorScheme))
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            Text(metaLabel)
                .font(.caption2)
                .foregroundStyle(Color.taskCardSecondary(for: colorScheme))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardFill)
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8,
                style: .continuous
            )
            .fill(accent)
            .frame(height: 4)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 0.5)
        }
    }

    private var cardFill: Color {
        accent.opacity(colorScheme == .dark ? 0.58 : 0.46)
    }

    private var metaLabel: String {
        if task.isAllDay {
            return AppLocalized.string(L10n.Common.allDay, locale: locale)
        }
        let start = ScheduleTimeFormatting.timelineClockTime(
            task.scheduleStartDate,
            locale: locale
        )
        let duration = WeekAgendaDurationFormatting.shortLabel(
            from: task.scheduleStartDate,
            to: task.timelineEndDate,
            locale: locale
        )
        if let duration, duration.isEmpty == false {
            return "\(start) · \(duration)"
        }
        return start
    }
}

private enum WeekAgendaDurationFormatting {
    static func shortLabel(from start: Date, to end: Date, locale: Locale) -> String? {
        let seconds = max(0, end.timeIntervalSince(start))
        let totalMinutes = Int((seconds / 60.0).rounded())
        guard totalMinutes > 0 else { return nil }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return String(format: "%dh %dmin", hours, minutes)
        }
        if hours > 0 {
            return String(format: "%dh", hours)
        }
        return String(format: "%dmin", minutes)
    }
}

#if canImport(UIKit)
import UIKit

/// 让 page TabView 的分页手势等待内层横向 ScrollView 失败后再触发：
/// 卡片还能横滑时由任务条响应；滑到尽头或无法继续时再换周。
private struct WeekAgendaNestedScrollGestureBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            Self.linkPagingScroll(toFailAfterNestedScrollNear: uiView)
        }
    }

    private static func linkPagingScroll(toFailAfterNestedScrollNear anchor: UIView) {
        guard let nested = nearestHorizontalScrollView(from: anchor) else { return }
        guard let paging = nearestPagingScrollView(from: nested) else { return }
        guard paging !== nested else { return }

        // 分页手势等内层横滑失败后再识别：内层还能滑时不换周。
        paging.panGestureRecognizer.require(toFail: nested.panGestureRecognizer)
    }

    private static func nearestHorizontalScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let node = current {
            if let scroll = node as? UIScrollView,
               scroll.isPagingEnabled == false,
               scroll.contentSize.width > scroll.bounds.width + 1 {
                return scroll
            }
            for child in node.subviews {
                if let scroll = child as? UIScrollView,
                   scroll.isPagingEnabled == false,
                   scroll.contentSize.width > scroll.bounds.width + 1 {
                    return scroll
                }
            }
            // 同级兄弟（SwiftUI background 常与 ScrollView 宿主并列）。
            if let parent = node.superview {
                for sibling in parent.subviews where sibling !== node {
                    if let scroll = sibling as? UIScrollView,
                       scroll.isPagingEnabled == false {
                        return scroll
                    }
                    if let scroll = firstHorizontalScrollView(in: sibling) {
                        return scroll
                    }
                }
            }
            current = node.superview
        }
        return nil
    }

    private static func firstHorizontalScrollView(in root: UIView) -> UIScrollView? {
        var stack: [UIView] = [root]
        while let node = stack.popLast() {
            if let scroll = node as? UIScrollView,
               scroll.isPagingEnabled == false {
                return scroll
            }
            stack.append(contentsOf: node.subviews)
        }
        return nil
    }

    private static func nearestPagingScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view.superview
        while let node = current {
            if let scroll = node as? UIScrollView, scroll.isPagingEnabled {
                return scroll
            }
            current = node.superview
        }
        return nil
    }
}
#endif

#Preview {
    TaskWeekGridView(
        selectedDate: .constant(Date()),
        viewModel: AppViewModels.makeScheduleViewModel(),
        onTaskSelect: { _ in }
    )
}
