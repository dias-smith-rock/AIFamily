import SwiftUI

private struct WeekPageBundle {
    let offset: Int
    let days: [Date]
    let tasks: [FamilyTask]
}

/// Week 模式：7 日 × 24 小时时间网格（由 `TaskListView` 嵌入）。
struct TaskWeekGridView: View {
    @Environment(\.locale) private var locale

    @ObservedObject var viewModel: ScheduleViewModel
    @Binding var selectedDate: Date

    let onTaskSelect: (FamilyTask) -> Void
    let onRefresh: (() async -> Void)?

    @State private var weekEpochStart: Date = ScheduleWeekCalendar.startOfWeek(for: Date())
    @State private var weekOffset: Int = 0
    /// 三页窗口：0 上一周 / 1 当前周 / 2 下一周。
    @State private var pagerSlot: Int = ScheduleWeekCalendar.pagerCenterSlot
    @State private var gridColumnWidth: CGFloat = 0

    private let horizontalPadding: CGFloat = 16

    init(
        selectedDate: Binding<Date>,
        viewModel: ScheduleViewModel,
        onTaskSelect: @escaping (FamilyTask) -> Void,
        onRefresh: (() async -> Void)? = nil
    ) {
        self._selectedDate = selectedDate
        self.viewModel = viewModel
        self.onTaskSelect = onTaskSelect
        self.onRefresh = onRefresh
    }

    var body: some View {
        Group {
            if viewModel.isLoading, viewModel.tasks.isEmpty {
                ProgressView(AppLocalized.string(L10n.Schedule.loadingTasks, locale: locale))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.tasks.isEmpty {
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
        .background(AppTheme.ColorToken.background.ignoresSafeArea())
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
        }
        .onChange(of: weekOffset) { oldOffset, newOffset in
            WeekViewPerformanceTracer.recordWeekOffsetChange(from: oldOffset, to: newOffset)
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
    }

    // MARK: - Week pager

    /// 三页窗口侧滑：周头与周体各仅挂载 prev / current / next 三周，任务在 pager 层一次性过滤。
    private var weekPager: some View {
        let previousBundle = weekPageBundle(offset: weekOffset - 1)
        let currentBundle = weekPageBundle(offset: weekOffset)
        let nextBundle = weekPageBundle(offset: weekOffset + 1)

        return VStack(alignment: .leading, spacing: 10) {
            weekHeaderSection(
                previous: previousBundle,
                current: currentBundle,
                next: nextBundle
            )

            weekBodySection(
                previous: previousBundle,
                current: currentBundle,
                next: nextBundle
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            WeekViewPerformanceTracer.mark("weekPager.onAppear")
        }
    }

    private func weekHeaderSection(
        previous: WeekPageBundle,
        current: WeekPageBundle,
        next: WeekPageBundle
    ) -> some View {
        TabView(selection: $pagerSlot) {
            weekHeaderPage(bundle: previous, slot: 0)
            weekHeaderPage(bundle: current, slot: ScheduleWeekCalendar.pagerCenterSlot)
            weekHeaderPage(bundle: next, slot: 2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 84, alignment: .top)
    }

    private func weekHeaderPage(bundle: WeekPageBundle, slot: Int) -> some View {
        weekHeaderRow(days: bundle.days, weekTasks: bundle.tasks)
            .padding(.horizontal, horizontalPadding)
            .tag(slot)
            .onAppear {
                WeekViewPerformanceTracer.recordWeekHeaderPageAppear(offset: bundle.offset)
            }
    }

    private func weekBodySection(
        previous: WeekPageBundle,
        current: WeekPageBundle,
        next: WeekPageBundle
    ) -> some View {
        TabView(selection: $pagerSlot) {
            weekBody(bundle: previous, slot: 0)
            weekBody(bundle: current, slot: ScheduleWeekCalendar.pagerCenterSlot)
            weekBody(bundle: next, slot: 2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func weekBody(bundle: WeekPageBundle, slot: Int) -> some View {
        let days = bundle.days
        let weekTasks = bundle.tasks
        let offset = bundle.offset

        return VStack(alignment: .leading, spacing: 10) {
            if hasAllDayTasks(in: weekTasks, days: days) {
                allDayStrip(days: days, weekTasks: weekTasks)
                    .padding(.horizontal, horizontalPadding)
            }

            ZStack(alignment: .bottomTrailing) {
                timelineScrollArea(
                    days: days,
                    weekTasks: weekTasks,
                    displayedWeekOffset: offset
                )

                if isDisplayingCurrentWeek(offset: offset) == false {
                    backToCurrentWeekButton
                        .padding(.trailing, horizontalPadding + 4)
                        .padding(.bottom, 16)
                        .transition(.scale.combined(with: .opacity))
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
        guard oldSlot != newSlot else { return }
        switch newSlot {
        case 0:
            WeekViewPerformanceTracer.notePendingWeekOffsetChange(source: "tabViewSwipe")
            shiftDisplayedWeek(by: -1)
            recenterPagerSlot()
        case 2:
            WeekViewPerformanceTracer.notePendingWeekOffsetChange(source: "tabViewSwipe")
            shiftDisplayedWeek(by: 1)
            recenterPagerSlot()
        default:
            break
        }
    }

    private func shiftDisplayedWeek(by weeks: Int) {
        weekOffset += weeks
        normalizeEpochIfNeeded()
        let calendar = Calendar.current
        if let shiftedDate = calendar.date(byAdding: .day, value: weeks * 7, to: selectedDate) {
            selectedDate = calendar.startOfDay(for: shiftedDate)
        }
    }

    private func applyWeekOffset(_ target: Int, animated: Bool) {
        let updates = {
            weekOffset = target
            pagerSlot = ScheduleWeekCalendar.pagerCenterSlot
        }
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
    }

    private func recenterPagerSlot() {
        guard pagerSlot != ScheduleWeekCalendar.pagerCenterSlot else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pagerSlot = ScheduleWeekCalendar.pagerCenterSlot
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
            Color.clear
                .frame(width: ScheduleTimelineMetrics.timeColumnWidth)

            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    weekDayHeaderCell(for: day, weekTasks: weekTasks)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func weekDayHeaderCell(for day: Date, weekTasks: [FamilyTask]) -> some View {
        let selected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDateInToday(day)
        let count = taskCount(for: day, in: weekTasks)

        return Button {
            selectedDate = Calendar.current.startOfDay(for: day)
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(selected ? AppTheme.ColorToken.accent : .secondary)

                Text(String(Calendar.current.component(.day, from: day)))
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

    private func taskCount(for date: Date, in weekTasks: [FamilyTask]) -> Int {
        weekTasks.filter { Calendar.current.isDate(taskDisplayDate($0), inSameDayAs: date) }.count
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
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemBackground).opacity(0.9))
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.taskCardLeadingAccent(fromHex: task.backgroundColor))
                                .frame(width: 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 1)
    }

    // MARK: - Timeline grid

    private func timelineScrollArea(days: [Date], weekTasks: [FamilyTask], displayedWeekOffset: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    timeLabelsColumn
                        .frame(width: ScheduleTimelineMetrics.timeColumnWidth)

                    GeometryReader { geometry in
                        let gridWidth = geometry.size.width
                        let columnWidth = gridWidth / 7
                        let layoutItems = WeekViewPerformanceTracer.measureLayoutEngine(
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

                            if let nowY = currentTimeYOffset(in: days) {
                                nowIndicator(y: nowY, gridWidth: gridWidth)

                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .offset(y: max(0, nowY - 80))
                                    .id(WeekGridScrollIDs.timeAnchor(for: displayedWeekOffset))
                            }

                            ForEach(layoutItems) { item in
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
                            if abs(gridColumnWidth - columnWidth) > 0.5 {
                                gridColumnWidth = columnWidth
                            }
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            let updated = newWidth / 7
                            if abs(gridColumnWidth - updated) > 0.5 {
                                gridColumnWidth = updated
                            }
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
                await refreshTasks()
            }
            .onAppear {
                WeekViewPerformanceTracer.recordTimelineScrollAppear(
                    weekOffset: displayedWeekOffset,
                    weekTaskCount: weekTasks.count
                )
                scrollToInitialTime(
                    proxy: proxy,
                    days: days,
                    displayedWeekOffset: displayedWeekOffset,
                    animated: false
                )
            }
            .onChange(of: weekOffset) { _, _ in
                scrollToInitialTime(
                    proxy: proxy,
                    days: days,
                    displayedWeekOffset: displayedWeekOffset,
                    animated: true
                )
            }
        }
    }

    private var timeLabelsColumn: some View {
        VStack(spacing: 0) {
            ForEach(0..<WeekGridMetrics.hoursPerDay, id: \.self) { hour in
                Text(hourLabel(for: hour))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(height: WeekGridMetrics.hourRowHeight, alignment: .top)
                    .offset(y: -6)
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

    // MARK: - Back to current week

    private var backToCurrentWeekButton: some View {
        Button(action: jumpToCurrentWeek) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(AppTheme.ColorToken.accent)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Common.today.localized)
    }

    private func isDisplayingCurrentWeek(offset: Int) -> Bool {
        offset == ScheduleWeekCalendar.weekOffset(for: Date(), epochStart: weekEpochStart)
    }

    private func jumpToCurrentWeek() {
        let today = Calendar.current.startOfDay(for: Date())
        let targetOffset = ScheduleWeekCalendar.weekOffset(for: today, epochStart: weekEpochStart)
        WeekViewPerformanceTracer.notePendingWeekOffsetChange(source: "jumpToCurrentWeek")
        withAnimation(.easeInOut(duration: 0.25)) {
            weekOffset = targetOffset
            selectedDate = today
            pagerSlot = ScheduleWeekCalendar.pagerCenterSlot
        }
    }

    // MARK: - Task filtering

    private func filteredTasks(for days: [Date]) -> [FamilyTask] {
        guard let first = days.first, let last = days.last else { return [] }
        let cal = Calendar.current
        let weekStart = cal.startOfDay(for: first)
        let weekEnd = cal.startOfDay(for: last)
        return WeekViewPerformanceTracer.measureTasksFilter(
            scheduledTaskCount: viewModel.scheduledTasks.count
        ) {
            viewModel.scheduledTasks.filter { task in
                let day = cal.startOfDay(for: taskDisplayDate(task))
                return day >= weekStart && day <= weekEnd
            }
        }
    }

    private func allDayTasks(for day: Date, in weekTasks: [FamilyTask]) -> [FamilyTask] {
        weekTasks.filter { task in
            task.isAllDay && Calendar.current.isDate(taskDisplayDate(task), inSameDayAs: day)
        }
    }

    private func hasAllDayTasks(in weekTasks: [FamilyTask], days: [Date]) -> Bool {
        days.contains { allDayTasks(for: $0, in: weekTasks).isEmpty == false }
    }

    private func taskDisplayDate(_ task: FamilyTask) -> Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private func currentTimeYOffset(in days: [Date]) -> CGFloat? {
        guard days.contains(where: { Calendar.current.isDateInToday($0) }) else { return nil }
        return WeekTaskLayoutEngine.yOffset(for: Date())
    }

    private func scrollToInitialTime(
        proxy: ScrollViewProxy,
        days: [Date],
        displayedWeekOffset: Int,
        animated: Bool
    ) {
        guard days.contains(where: { Calendar.current.isDateInToday($0) }) else { return }
        let anchorID = WeekGridScrollIDs.timeAnchor(for: displayedWeekOffset)
        let action = {
            proxy.scrollTo(anchorID, anchor: .top)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
        }
    }

    private func refreshTasks() async {
        if let onRefresh {
            await onRefresh()
        } else {
            await viewModel.loadTasks()
        }
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
    }
}

// MARK: - Event card

private struct WeekTaskEventCard: View {
    let task: FamilyTask
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.tertiarySystemBackground))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.taskCardLeadingAccent(fromHex: task.backgroundColor))
                    .frame(width: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AppTheme.ColorToken.border, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

private enum WeekGridScrollIDs {
    static func timeAnchor(for weekOffset: Int) -> String {
        "week-grid-time-anchor-\(weekOffset)"
    }
}

#Preview {
    TaskWeekGridView(
        selectedDate: .constant(Date()),
        viewModel: AppViewModels.makeScheduleViewModel(),
        onTaskSelect: { _ in }
    )
}
