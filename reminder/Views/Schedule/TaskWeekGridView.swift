import SwiftUI

private struct WeekPageBundle {
    let offset: Int
    let days: [Date]
    let tasks: [FamilyTask]
}

/// Week 模式：7 日 × 24 小时时间网格（由 `TaskListView` 嵌入）。
struct TaskWeekGridView: View {
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appSettings: AppSettingsManager

    @ObservedObject var viewModel: ScheduleViewModel
    @Binding var selectedDate: Date

    private var displayCalendar: Calendar { appSettings.effectiveCalendar }

    let onTaskSelect: (FamilyTask) -> Void
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
    @State private var gridColumnWidth: CGFloat = 0
    /// A：首帧后再挂载当前周 1440pt 时间网格。
    @State private var isCurrentWeekTimelineReady = false
    /// C：首帧后再挂载上一周 / 下一周页（含任务过滤与网格）。
    @State private var isAdjacentWeekPagesReady = false
    @State private var firstPaintExpansionTask: Task<Void, Never>?
    @State private var pendingTimelineScrollMode: WeekTimelineScrollMode?
    @State private var divisionAvoidanceInsets = EdgeInsets()

    private let horizontalPadding: CGFloat = 16

    init(
        selectedDate: Binding<Date>,
        viewModel: ScheduleViewModel,
        onTaskSelect: @escaping (FamilyTask) -> Void,
        onRefresh: (() async -> Void)? = nil,
        showsBackToCurrentWeekButton: Binding<Bool> = .constant(false),
        backToCurrentWeekTrigger: Binding<Int> = .constant(0)
    ) {
        self._selectedDate = selectedDate
        self.viewModel = viewModel
        self.onTaskSelect = onTaskSelect
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
        // 侧栏 Tab / Duo 折痕：列宽跟 GeometryReader 走，额外避让 chrome 与 division。
        .duoCanvasChromePadding(extra: divisionAvoidanceInsets)
        .background {
            GeometryReader { geo in
                let metrics = geo.duoLayoutMetrics(horizontalSizeClass: horizontalSizeClass)
                Color.clear
                    .onAppear { divisionAvoidanceInsets = metrics.divisionAvoidanceInsets }
                    .onChange(of: geo.size) { _, _ in
                        divisionAvoidanceInsets = geo.duoLayoutMetrics(
                            horizontalSizeClass: horizontalSizeClass
                        ).divisionAvoidanceInsets
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
        .onChange(of: isCurrentWeekTimelineReady) { oldValue, newValue in
            WeekViewPerformanceTracer.mark(
                "isCurrentWeekTimelineReady.changed",
                note: "from=\(oldValue) to=\(newValue) weekOffset=\(weekOffset)"
            )
        }
        .onChange(of: backToCurrentWeekTrigger) { oldValue, newValue in
            guard newValue != oldValue else { return }
            jumpToCurrentWeek()
        }
    }

    // MARK: - Week pager

    /// 单 `TabView` 三页窗口：周头与网格同页侧滑，避免双 TabView 抢 selection。
    /// 首帧仅当前周（周头 + 全天条 + 网格占位），次帧再展开邻周与完整网格。
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

    /// 单页完整内容：周头 + 全天条 + 时间网格（与侧滑同源）。
    private func weekPage(bundle: WeekPageBundle, slot: Int) -> some View {
        let days = bundle.days
        let weekTasks = bundle.tasks
        let offset = bundle.offset
        let isCenterPage = slot == ScheduleWeekCalendar.pagerCenterSlot
        let shouldShowTimeline = isCenterPage == false || isCurrentWeekTimelineReady

        return VStack(alignment: .leading, spacing: 10) {
            ScheduleWeekDayStripChrome {
                weekHeaderRow(days: days, weekTasks: weekTasks)
                    .onAppear {
                        WeekViewPerformanceTracer.recordWeekHeaderPageAppear(offset: offset)
                    }
            }

            if hasAllDayTasks(in: weekTasks, days: days) {
                allDayStrip(days: days, weekTasks: weekTasks)
                    .padding(.horizontal, horizontalPadding)
            }

            Group {
                if shouldShowTimeline {
                    WeekTimelineScrollArea(
                        days: days,
                        weekTasks: weekTasks,
                        displayedWeekOffset: offset,
                        weekOffset: weekOffset,
                        pagerSlot: pagerSlot,
                        isCurrentWeekTimelineReady: isCurrentWeekTimelineReady,
                        isAdjacentWeekPagesReady: isAdjacentWeekPagesReady,
                        pendingTimelineScrollMode: $pendingTimelineScrollMode,
                        gridColumnWidth: $gridColumnWidth,
                        horizontalPadding: horizontalPadding,
                        viewModel: viewModel,
                        onTaskSelect: onTaskSelect,
                        onRefresh: refreshTasks,
                        taskDisplayDate: taskDisplayDate
                    )
                } else {
                    timelineGridPlaceholder
                        .onAppear {
                            WeekViewPerformanceTracer.recordTimelinePlaceholderAppear(
                                displayedWeekOffset: offset,
                                isCenterPage: isCenterPage,
                                isCurrentWeekTimelineReady: isCurrentWeekTimelineReady
                            )
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: isDisplayingCurrentWeek(offset: offset))
        .tag(slot)
        .id(offset)
        .onAppear {
            WeekViewPerformanceTracer.recordWeekBodyAppear(offset: offset)
        }
    }

    private var timelineGridPlaceholder: some View {
        AppTheme.ColorToken.surface
            .frame(maxWidth: .infinity)
            .frame(height: WeekGridMetrics.gridHeight)
            .overlay {
                ProgressView()
            }
    }

    // MARK: - First paint expansion

    private func scheduleFirstPaintExpansion() {
        guard isCurrentWeekTimelineReady == false || isAdjacentWeekPagesReady == false else {
            return
        }
        firstPaintExpansionTask?.cancel()
        firstPaintExpansionTask = Task { @MainActor in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            expandFirstPaintContent()
        }
    }

    private func ensureFirstPaintExpanded() {
        guard isCurrentWeekTimelineReady == false || isAdjacentWeekPagesReady == false else {
            return
        }
        firstPaintExpansionTask?.cancel()
        firstPaintExpansionTask = nil
        expandFirstPaintContent()
    }

    private func expandFirstPaintContent() {
        guard isCurrentWeekTimelineReady == false || isAdjacentWeekPagesReady == false else {
            return
        }
        WeekViewPerformanceTracer.mark(
            "firstPaint.expand",
            note: "enablingTimelineAndAdjacentPages"
        )
        WeekViewPerformanceTracer.recordFirstPaintExpandScrollContext(
            weekOffset: weekOffset,
            isDisplayingCurrentWeek: isDisplayingCurrentWeek(offset: weekOffset),
            isCurrentWeekTimelineReadyBefore: isCurrentWeekTimelineReady
        )
        isCurrentWeekTimelineReady = true
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
        pendingTimelineScrollMode = .earliestTask
        // 同一无动画事务内：换周 + 回中，避免手势动画未结束时双驱动打架。
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

    /// 侧滑换周后的原子提交：`weekOffset`/`selectedDate` 与 `pagerSlot` 回中同事务。
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
        if target != weekOffset {
            pendingTimelineScrollMode = .earliestTask
        }
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
            // 等 TabView 消化程序化 selection，再恢复手势，避免回写 onChange 重入。
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

    // MARK: - Header

    private func weekHeaderRow(days: [Date], weekTasks: [FamilyTask]) -> some View {
        HStack(spacing: 0) {
            // 与下方时间轴 gutter 对齐，使日列落在网格列中心。
            Color.clear
                .frame(width: ScheduleTimelineMetrics.timeColumnWidth)

            ForEach(days, id: \.self) { day in
                ScheduleWeekDayStripCell(
                    date: day,
                    isSelected: displayCalendar.isDate(day, inSameDayAs: selectedDate),
                    taskCount: taskCount(for: day, in: weekTasks),
                    locale: locale
                ) {
                    selectedDate = displayCalendar.startOfDay(for: day)
                }
            }
        }
    }

    private func taskCount(for date: Date, in weekTasks: [FamilyTask]) -> Int {
        weekTasks.filter {
            displayCalendar.isDate(
                $0.scheduleDisplayDay(displayCalendar: displayCalendar),
                inSameDayAs: date
            )
        }.count
    }

    // MARK: - All-day strip

    private func allDayStrip(days: [Date], weekTasks: [FamilyTask]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(L10n.Common.allDay.localized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: ScheduleTimelineMetrics.timeColumnWidth, alignment: .trailing)
                .padding(.top, 2)

            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    allDayColumn(for: day, tasks: allDayTasks(for: day, in: weekTasks))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func allDayColumn(for day: Date, tasks: [FamilyTask]) -> some View {
        VStack(spacing: 3) {
            ForEach(tasks) { task in
                Button {
                    onTaskSelect(task)
                } label: {
                    Text(viewModel.displayTitle(for: task))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.taskCardTitle(for: colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .taskCardSurface(
                            for: task,
                            cornerRadius: 4,
                            headerBarWidth: 3
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 1)
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
        pendingTimelineScrollMode = .currentTime
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

    private func allDayTasks(for day: Date, in weekTasks: [FamilyTask]) -> [FamilyTask] {
        weekTasks.filter { task in
            task.isAllDay
                && displayCalendar.isDate(
                    task.scheduleDisplayDay(displayCalendar: displayCalendar),
                    inSameDayAs: day
                )
        }
    }

    private func hasAllDayTasks(in weekTasks: [FamilyTask], days: [Date]) -> Bool {
        days.contains { allDayTasks(for: $0, in: weekTasks).isEmpty == false }
    }

    private func taskDisplayDate(_ task: FamilyTask) -> Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private func refreshTasks() async {
        if let onRefresh {
            await onRefresh()
        } else {
            await viewModel.loadTasks()
        }
    }
}

private enum WeekTimelineScrollMode {
    /// 首帧进入：含今天则滚到此刻，否则滚到最早任务。
    case currentTimeIfToday
    /// 强制滚到此刻（如「回到本周」）。
    case currentTime
    /// 滚到当周最早定时任务顶部（侧滑换周后）。
    case earliestTask
}

// MARK: - Timeline scroll area

private struct WeekTimelineScrollArea: View {
    let days: [Date]
    let weekTasks: [FamilyTask]
    let displayedWeekOffset: Int
    let weekOffset: Int
    let pagerSlot: Int
    let isCurrentWeekTimelineReady: Bool
    let isAdjacentWeekPagesReady: Bool
    @Binding var pendingTimelineScrollMode: WeekTimelineScrollMode?
    @Binding var gridColumnWidth: CGFloat
    let horizontalPadding: CGFloat
    @ObservedObject var viewModel: ScheduleViewModel
    let onTaskSelect: (FamilyTask) -> Void
    let onRefresh: () async -> Void
    let taskDisplayDate: (FamilyTask) -> Date

    @State private var activeScrollMode: WeekTimelineScrollMode = .currentTimeIfToday
    @State private var cachedLayoutItems: [WeekTaskLayoutItem] = []
    @State private var cachedLayoutColumnWidth: CGFloat = 0
    @State private var cachedLayoutSignature: UInt64 = 0

    private var isActiveWeekPage: Bool { displayedWeekOffset == weekOffset }
    private var containsToday: Bool {
        let calendar = AppDisplayTimeZone.calendar()
        return days.contains(where: { calendar.isDateInToday($0) })
    }

    private var nowY: CGFloat? {
        guard containsToday else { return nil }
        return WeekTaskLayoutEngine.yOffset(for: Date())
    }

    private var earliestTaskStartY: CGFloat? {
        WeekTaskLayoutEngine.earliestTimedTaskStartY(
            tasks: weekTasks,
            taskStart: taskDisplayDate
        )
    }

    private var scrollAnchorID: String {
        WeekGridScrollIDs.scrollAnchor(for: displayedWeekOffset)
    }

    private var fractionalHourNow: CGFloat {
        WeekTaskLayoutEngine.fractionalHour(for: Date())
    }

    private var nowHour: Int {
        Int(fractionalHourNow)
    }

    private var nowYOffsetWithinHour: CGFloat {
        (fractionalHourNow - CGFloat(nowHour)) * WeekGridMetrics.hourRowHeight
    }

    private var layoutInputFingerprint: UInt64 {
        weekLayoutSignature(tasks: weekTasks, days: days)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    timeLabelsColumn {
                        alignTimeline(
                            using: proxy,
                            mode: activeScrollMode,
                            source: "scrollAnchor.onAppear",
                            animated: false
                        )
                    }
                    .frame(width: ScheduleTimelineMetrics.timeColumnWidth)

                    GeometryReader { geometry in
                    let gridWidth = geometry.size.width
                    let columnWidth = gridWidth / 7
                    let _ = WeekViewPerformanceTracer.recordGeometryLayoutPass(
                        columnWidth: columnWidth,
                        weekTaskCount: weekTasks.count
                    )

                    ZStack(alignment: .topLeading) {
                        AppTheme.ColorToken.surface

                        WeekGridBackground(
                            columnWidth: columnWidth,
                            columnCount: 7
                        )
                        .frame(width: gridWidth, height: WeekGridMetrics.gridHeight)

                        if let nowY {
                            nowIndicator(y: nowY, gridWidth: gridWidth)
                        }

                        ForEach(cachedLayoutItems) { item in
                            Button {
                                onTaskSelect(item.task)
                            } label: {
                                WeekTaskEventCard(
                                    task: item.task,
                                    title: viewModel.displayTitle(for: item.task)
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(width: item.frame.width, height: item.frame.height)
                            .offset(x: item.frame.minX, y: item.frame.minY)
                        }
                    }
                    .frame(width: gridWidth, height: WeekGridMetrics.gridHeight, alignment: .topLeading)
                    .onAppear {
                        rebuildCachedLayoutIfNeeded(columnWidth: columnWidth)
                        if abs(gridColumnWidth - columnWidth) > 0.5 {
                            gridColumnWidth = columnWidth
                        }
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        let updated = newWidth / 7
                        rebuildCachedLayoutIfNeeded(columnWidth: updated)
                        if abs(gridColumnWidth - updated) > 0.5 {
                            gridColumnWidth = updated
                        }
                    }
                    .onChange(of: layoutInputFingerprint) { _, _ in
                        rebuildCachedLayoutIfNeeded(columnWidth: columnWidth, force: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: WeekGridMetrics.gridHeight)
            }
            .padding(.top, 6)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 24)
        }
        .refreshable {
            await onRefresh()
        }
        .onAppear {
            WeekViewPerformanceTracer.recordTimelineScrollAppear(
                weekOffset: displayedWeekOffset,
                weekTaskCount: weekTasks.count
            )
            scheduleTimelineAlignRetry(
                using: proxy,
                mode: .currentTimeIfToday,
                source: "timelineScrollArea.onAppear"
            )
        }
        .onChange(of: weekOffset) { _, newOffset in
            guard displayedWeekOffset == newOffset else { return }
            let mode = pendingTimelineScrollMode ?? .earliestTask
            pendingTimelineScrollMode = nil
            scheduleTimelineAlignRetry(
                using: proxy,
                mode: mode,
                source: "timelineScrollArea.weekOffsetChanged"
            )
        }
        .onChange(of: isCurrentWeekTimelineReady) { _, isReady in
            guard isReady else { return }
            scheduleTimelineAlignRetry(
                using: proxy,
                mode: .currentTimeIfToday,
                source: "isCurrentWeekTimelineReady"
            )
        }
        }
    }

    private func timeLabelsColumn(onAnchorAppear: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<WeekGridMetrics.hoursPerDay, id: \.self) { hour in
                let rowTopPadding: CGFloat = hour == 0 ? 2 : 0
                Text(hourLabel(for: hour))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.top, rowTopPadding)
                    .frame(height: WeekGridMetrics.hourRowHeight, alignment: .top)
                    .offset(y: hour == 0 ? 0 : -6)
                    .overlay(alignment: .top) {
                        if isActiveWeekPage,
                           let placement = scrollAnchorPlacement(for: activeScrollMode),
                           hour == placement.hour {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .padding(.top, placement.offsetInHour + placement.rowTopPadding)
                                .id(scrollAnchorID)
                                .onAppear {
                                    WeekViewPerformanceTracer.recordScrollAnchorAppear(
                                        displayedWeekOffset: displayedWeekOffset,
                                        nowY: placement.offsetY,
                                        anchorOffsetY: placement.offsetY,
                                        anchorID: scrollAnchorID,
                                        anchorParent: "hourRow"
                                    )
                                    onAnchorAppear()
                                }
                        }
                    }
            }
        }
    }

    private func hourLabel(for hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func nowIndicator(y: CGFloat, gridWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.red)
                .frame(width: gridWidth, height: 1)
                .offset(y: y)

            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .offset(x: -3, y: y - 3)
        }
        .allowsHitTesting(false)
    }

    private struct ScrollAnchorPlacement {
        let hour: Int
        let offsetInHour: CGFloat
        let rowTopPadding: CGFloat
        let offsetY: CGFloat
    }

    private func scrollAnchorPlacement(for mode: WeekTimelineScrollMode) -> ScrollAnchorPlacement? {
        switch mode {
        case .currentTime:
            guard containsToday else { return scrollAnchorPlacement(for: .earliestTask) }
            return placement(forYOffset: nowY ?? 0, hour: nowHour, offsetInHour: nowYOffsetWithinHour)
        case .currentTimeIfToday:
            if containsToday {
                return placement(forYOffset: nowY ?? 0, hour: nowHour, offsetInHour: nowYOffsetWithinHour)
            }
            return scrollAnchorPlacement(for: .earliestTask)
        case .earliestTask:
            if let earliestTaskStartY {
                return placement(forYOffset: earliestTaskStartY)
            }
            return placement(forYOffset: 0, hour: 0, offsetInHour: 0)
        }
    }

    private func placement(
        forYOffset yOffset: CGFloat,
        hour: Int? = nil,
        offsetInHour: CGFloat? = nil
    ) -> ScrollAnchorPlacement {
        let resolvedHour = hour ?? min(23, max(0, Int(yOffset / WeekGridMetrics.hourRowHeight)))
        let resolvedOffsetInHour = offsetInHour
            ?? (yOffset - CGFloat(resolvedHour) * WeekGridMetrics.hourRowHeight)
        let rowTopPadding: CGFloat = resolvedHour == 0 ? 2 : 0
        return ScrollAnchorPlacement(
            hour: resolvedHour,
            offsetInHour: resolvedOffsetInHour,
            rowTopPadding: rowTopPadding,
            offsetY: yOffset
        )
    }

    private func viewportAnchor(for mode: WeekTimelineScrollMode) -> UnitPoint {
        switch mode {
        case .currentTime, .currentTimeIfToday where containsToday:
            return WeekGridScrollIDs.currentTimeScrollViewportAnchor
        default:
            return WeekGridScrollIDs.earliestTaskScrollViewportAnchor
        }
    }

    private func alignTimeline(
        using proxy: ScrollViewProxy,
        mode: WeekTimelineScrollMode,
        source: String,
        animated: Bool
    ) {
        guard isActiveWeekPage else {
            WeekViewPerformanceTracer.recordScrollToNowSkipped(
                source: source,
                reason: "displayedWeekOffsetMismatch"
            )
            return
        }

        activeScrollMode = mode

        guard scrollAnchorPlacement(for: mode) != nil else {
            WeekViewPerformanceTracer.recordScrollToNowSkipped(
                source: source,
                reason: "noScrollAnchor"
            )
            return
        }

        let resolvedAnchorY = scrollAnchorPlacement(for: mode)?.offsetY

        WeekViewPerformanceTracer.recordScrollToNowAttempt(
            source: source,
            displayedWeekOffset: displayedWeekOffset,
            weekOffset: weekOffset,
            pagerSlot: pagerSlot,
            isCurrentWeekTimelineReady: isCurrentWeekTimelineReady,
            isAdjacentWeekPagesReady: isAdjacentWeekPagesReady,
            containsToday: containsToday,
            isDisplayingCurrentWeek: isActiveWeekPage && containsToday,
            nowY: resolvedAnchorY,
            anchorID: scrollAnchorID,
            animated: animated,
            scrollMode: String(describing: mode)
        )

        let applyScroll = {
            WeekViewPerformanceTracer.recordScrollToNowInvoked(
                source: source,
                anchorID: scrollAnchorID,
                anchorOffsetY: resolvedAnchorY,
                animated: animated,
                scrollMode: String(describing: mode)
            )
            proxy.scrollTo(
                scrollAnchorID,
                anchor: viewportAnchor(for: mode)
            )
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                applyScroll()
            }
        } else {
            applyScroll()
        }
    }

    private func scheduleTimelineAlignRetry(
        using proxy: ScrollViewProxy,
        mode: WeekTimelineScrollMode,
        source: String
    ) {
        Task { @MainActor in
            await Task.yield()
            alignTimeline(using: proxy, mode: mode, source: "\(source).align", animated: false)
        }
    }

    private func rebuildCachedLayoutIfNeeded(columnWidth: CGFloat, force: Bool = false) {
        guard columnWidth > 1 else { return }
        let signature = weekLayoutSignature(tasks: weekTasks, days: days)
        let widthChanged = abs(cachedLayoutColumnWidth - columnWidth) > 0.5
        guard force || widthChanged || signature != cachedLayoutSignature else { return }

        cachedLayoutItems = WeekViewPerformanceTracer.measureLayoutEngine(
            taskCount: weekTasks.count,
            columnWidth: columnWidth
        ) {
            WeekTaskLayoutEngine.layout(
                tasks: weekTasks,
                weekDays: days,
                columnWidth: columnWidth,
                taskStart: taskDisplayDate,
                taskEnd: { $0.timelineEndDate }
            )
        }
        cachedLayoutColumnWidth = columnWidth
        cachedLayoutSignature = signature
    }

    private func weekLayoutSignature(tasks: [FamilyTask], days: [Date]) -> UInt64 {
        var hasher = Hasher()
        for day in days {
            hasher.combine(day.timeIntervalSince1970)
        }
        for task in tasks {
            hasher.combine(task.id)
            hasher.combine(task.dueDate?.timeIntervalSince1970)
            hasher.combine(task.endDatetime?.timeIntervalSince1970)
            hasher.combine(task.durationMinutes)
            hasher.combine(task.title)
        }
        return UInt64(truncatingIfNeeded: hasher.finalize())
    }
}


// MARK: - Grid background

private struct WeekGridBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let columnWidth: CGFloat
    let columnCount: Int

    private var lineColor: Color {
        switch colorScheme {
        case .dark:
            return Color(.separator).opacity(0.82)
        default:
            return Color(.separator).opacity(0.48)
        }
    }

    private var lineWidth: CGFloat {
        colorScheme == .dark ? 1 : 0.75
    }

    var body: some View {
        let _ = WeekViewPerformanceTracer.recordGridCanvasDraw()
        return Canvas { context, size in
            let strokeColor = lineColor
            let strokeWidth = lineWidth

            for hour in 0...WeekGridMetrics.hoursPerDay {
                let y = CGFloat(hour) * WeekGridMetrics.hourRowHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(strokeColor), lineWidth: strokeWidth)
            }

            for column in 0...columnCount {
                let x = CGFloat(column) * columnWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(strokeColor), lineWidth: strokeWidth)
            }
        }
        // 栅格化为位图，避免周页滑动 / ViewModel 刷新时反复矢量描边。
        .drawingGroup(opaque: false, colorMode: .nonLinear)
    }
}

// MARK: - Event card

private struct WeekTaskEventCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let task: FamilyTask
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.taskCardTitle(for: colorScheme))
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .taskCardSurface(
                for: task,
                cornerRadius: 4,
                headerBarWidth: 3
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(task.cardThemeAccentColor.opacity(0.9), lineWidth: 0.5)
            }
    }
}

private enum WeekGridScrollIDs {
    /// 当周自动滚动时，「此刻」线在可视区域内的纵向位置（中部偏上）。
    static let currentTimeScrollViewportAnchor = UnitPoint(x: 0, y: 0.34)
    /// 最早任务顶部对齐视口顶部。
    static let earliestTaskScrollViewportAnchor = UnitPoint.top

    static func scrollAnchor(for weekOffset: Int) -> String {
        "week-grid-scroll-anchor-\(weekOffset)"
    }
}

#Preview {
    TaskWeekGridView(
        selectedDate: .constant(Date()),
        viewModel: AppViewModels.makeScheduleViewModel(),
        onTaskSelect: { _ in }
    )
}
