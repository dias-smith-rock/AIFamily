import SwiftUI

/// 月视图：参考日历月板——月标题 + 网格线 + 格内任务条（含跨天条），左右滑换月。
struct TaskMonthView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appSettings: AppSettingsManager

    @Binding var selectedDate: Date
    let tasks: [FamilyTask]
    let titleForTask: (FamilyTask) -> String
    let onSelectDay: (Date) -> Void
    let onSelectTask: (FamilyTask) -> Void
    var onTaskComplete: ((FamilyTask) -> Void)? = nil
    var onTaskDelete: ((FamilyTask) -> Void)? = nil

    @Binding var showsBackToCurrentMonthButton: Bool
    @Binding var backToCurrentMonthTrigger: Int

    @State private var monthEpochStart: Date
    @State private var monthOffset: Int = 0
    @State private var pagerSlot: Int = 1
    @State private var isRecenteringPager = false
    @State private var pagerRecenterTask: Task<Void, Never>?

    private var calendar: Calendar { appSettings.effectiveCalendar }

    init(
        selectedDate: Binding<Date>,
        tasks: [FamilyTask],
        titleForTask: @escaping (FamilyTask) -> String,
        onSelectDay: @escaping (Date) -> Void,
        onSelectTask: @escaping (FamilyTask) -> Void,
        onTaskComplete: ((FamilyTask) -> Void)? = nil,
        onTaskDelete: ((FamilyTask) -> Void)? = nil,
        showsBackToCurrentMonthButton: Binding<Bool> = .constant(false),
        backToCurrentMonthTrigger: Binding<Int> = .constant(0)
    ) {
        self._selectedDate = selectedDate
        self.tasks = tasks
        self.titleForTask = titleForTask
        self.onSelectDay = onSelectDay
        self.onSelectTask = onSelectTask
        self.onTaskComplete = onTaskComplete
        self.onTaskDelete = onTaskDelete
        self._showsBackToCurrentMonthButton = showsBackToCurrentMonthButton
        self._backToCurrentMonthTrigger = backToCurrentMonthTrigger

        let cal = AppDisplayTimeZone.calendar()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        self._monthEpochStart = State(initialValue: start)
        let selectedStart = cal.date(
            from: cal.dateComponents([.year, .month], from: selectedDate.wrappedValue)
        ) ?? selectedDate.wrappedValue
        let initialOffset = cal.dateComponents([.month], from: start, to: selectedStart).month ?? 0
        self._monthOffset = State(initialValue: initialOffset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(monthTitle)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

            weekdayHeader
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            TabView(selection: $pagerSlot) {
                monthPage(offset: monthOffset - 1)
                    .tag(0)
                monthPage(offset: monthOffset)
                    .tag(1)
                monthPage(offset: monthOffset + 1)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(isRecenteringPager == false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .schedulePageBackground()
        .onAppear {
            syncMonthOffset(to: selectedDate, animated: false)
            syncBackToCurrentMonthButtonVisibility()
        }
        .onDisappear {
            pagerRecenterTask?.cancel()
            pagerRecenterTask = nil
            isRecenteringPager = false
            showsBackToCurrentMonthButton = false
        }
        .onChange(of: pagerSlot) { oldSlot, newSlot in
            handlePagerSlotChange(from: oldSlot, to: newSlot)
        }
        .onChange(of: selectedDate) { _, newValue in
            syncMonthOffset(to: newValue, animated: true)
        }
        .onChange(of: monthOffset) { _, _ in
            syncBackToCurrentMonthButtonVisibility()
        }
        .onChange(of: backToCurrentMonthTrigger) { oldValue, newValue in
            guard newValue != oldValue else { return }
            jumpToCurrentMonth()
        }
    }

    private var monthTitle: String {
        monthDate(for: monthOffset).formatted(
            .dateTime.month(.wide).year().locale(locale)
        )
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(localizedShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent.opacity(0.75))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var localizedShortWeekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        guard first > 0, first < symbols.count else { return symbols }
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private func monthPage(offset: Int) -> some View {
        let monthStart = monthDate(for: offset)
        return TaskMonthBoardPage(
            monthStart: monthStart,
            selectedDate: selectedDate,
            tasks: tasks,
            calendar: calendar,
            titleForTask: titleForTask,
            onSelectDay: { date in
                selectedDate = calendar.startOfDay(for: date)
                onSelectDay(date)
            },
            onSelectTask: onSelectTask,
            onTaskComplete: onTaskComplete,
            onTaskDelete: onTaskDelete
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .id(offset)
    }

    // MARK: - Pager

    private func handlePagerSlotChange(from oldSlot: Int, to newSlot: Int) {
        guard isRecenteringPager == false else { return }
        guard oldSlot != newSlot else { return }

        let delta: Int
        switch newSlot {
        case 0: delta = -1
        case 2: delta = 1
        default: return
        }

        isRecenteringPager = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            monthOffset += delta
            normalizeEpochIfNeeded()
            if let shifted = calendar.date(byAdding: .month, value: delta, to: selectedDate) {
                selectedDate = calendar.startOfDay(for: shifted)
            }
            pagerSlot = 1
        }
        scheduleClearPagerRecenterFlag()
    }

    private func syncMonthOffset(to date: Date, animated: Bool) {
        let target = monthOffset(for: date)
        guard target != monthOffset else { return }
        let updates = {
            monthOffset = target
            pagerSlot = 1
        }
        isRecenteringPager = true
        if animated {
            withAnimation(.easeInOut(duration: 0.25), updates)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, updates)
        }
        scheduleClearPagerRecenterFlag()
    }

    private func jumpToCurrentMonth() {
        let today = calendar.startOfDay(for: Date())
        selectedDate = today
        syncMonthOffset(to: today, animated: true)
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
        guard abs(monthOffset) > 18 else { return }
        monthEpochStart = monthDate(for: monthOffset)
        monthOffset = 0
    }

    private func monthDate(for offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: monthEpochStart)
            ?? monthEpochStart
    }

    private func monthOffset(for date: Date) -> Int {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? date
        return calendar.dateComponents([.month], from: monthEpochStart, to: start).month ?? 0
    }

    private func syncBackToCurrentMonthButtonVisibility() {
        let todayOffset = monthOffset(for: Date())
        let shouldShow = monthOffset != todayOffset
        if showsBackToCurrentMonthButton != shouldShow {
            showsBackToCurrentMonthButton = shouldShow
        }
    }
}

// MARK: - Board page (实际周行数，去掉整行空白)

private struct TaskMonthBoardPage: View {
    let monthStart: Date
    let selectedDate: Date
    let tasks: [FamilyTask]
    let calendar: Calendar
    let titleForTask: (FamilyTask) -> String
    let onSelectDay: (Date) -> Void
    let onSelectTask: (FamilyTask) -> Void
    var onTaskComplete: ((FamilyTask) -> Void)? = nil
    var onTaskDelete: ((FamilyTask) -> Void)? = nil

    private var cells: [YearDayCellData] {
        YearCalendarBuilder.monthGridCells(monthStart: monthStart, calendar: calendar)
    }

    /// 只保留含本月日期的周行，去掉末尾整行空白占位。
    private var weeks: [[YearDayCellData]] {
        let raw = stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
        return raw.filter { week in
            week.contains(where: \.isInMonth)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let weekRowCount = max(1, weeks.count)
            // 按实际周数均分可用高度，铺满且不纵向滚动。
            let rowHeight = max(0, geometry.size.height) / CGFloat(weekRowCount)
            VStack(spacing: 0) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    TaskMonthWeekRow(
                        weekCells: week,
                        selectedDate: selectedDate,
                        spans: MonthWeekSpanLayout.spans(
                            weekCells: week,
                            tasks: tasks,
                            calendar: calendar,
                            titleForTask: titleForTask
                        ),
                        calendar: calendar,
                        rowHeight: rowHeight,
                        onSelectDay: onSelectDay,
                        onSelectTask: onSelectTask,
                        onTaskComplete: onTaskComplete,
                        onTaskDelete: onTaskDelete
                    )
                    .frame(width: geometry.size.width, height: rowHeight)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .overlay {
                MonthGridLines(weekRowCount: weekRowCount)
            }
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Week row metrics

private struct TaskMonthRowMetrics {
    let dayNumberHeight: CGFloat
    let chipHeight: CGFloat
    let chipSpacing: CGFloat
    let chipTopInset: CGFloat
    let maxLanes: Int
    let titleFontSize: CGFloat

    /// 按行高推导日期区与任务条尺寸：优先加高单条，再均分行内剩余高度。
    static func make(rowHeight: CGFloat) -> TaskMonthRowMetrics {
        let dayNumberHeight = min(24, max(16, floor(rowHeight * 0.18)))
        let bottomPad: CGFloat = 4
        let chipTopInset: CGFloat = 2
        let chipSpacing: CGFloat = max(2, min(4, rowHeight * 0.025))
        let usable = max(0, rowHeight - dayNumberHeight - chipTopInset - bottomPad)

        // 目标条高约 20pt，避免为「塞满条数」把卡片压得过扁。
        let preferredChipHeight: CGFloat = min(28, max(16, floor(rowHeight * 0.22)))
        let minChipHeight: CGFloat = 14
        let laneBudget = max(1, Int(floor((usable + chipSpacing) / (preferredChipHeight + chipSpacing))))
        let maxLanes = min(4, max(1, laneBudget))
        let chipHeight = max(
            minChipHeight,
            floor((usable - chipSpacing * CGFloat(max(0, maxLanes - 1))) / CGFloat(maxLanes))
        )
        let titleFontSize = min(13, max(9, chipHeight * 0.55))
        return TaskMonthRowMetrics(
            dayNumberHeight: dayNumberHeight,
            chipHeight: chipHeight,
            chipSpacing: chipSpacing,
            chipTopInset: chipTopInset,
            maxLanes: maxLanes,
            titleFontSize: titleFontSize
        )
    }
}

// MARK: - Week row

private struct TaskMonthWeekRow: View {
    let weekCells: [YearDayCellData]
    let selectedDate: Date
    let spans: [MonthWeekSpanItem]
    let calendar: Calendar
    let rowHeight: CGFloat
    let onSelectDay: (Date) -> Void
    let onSelectTask: (FamilyTask) -> Void
    var onTaskComplete: ((FamilyTask) -> Void)? = nil
    var onTaskDelete: ((FamilyTask) -> Void)? = nil

    private var metrics: TaskMonthRowMetrics {
        TaskMonthRowMetrics.make(rowHeight: rowHeight)
    }

    var body: some View {
        let rowMetrics = metrics
        return GeometryReader { geo in
            let columnWidth = geo.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(weekCells) { cell in
                        dayBackgroundButton(cell: cell, dayNumberHeight: rowMetrics.dayNumberHeight)
                            .frame(width: columnWidth, height: rowHeight)
                    }
                }

                ForEach(spans.filter { $0.lane < rowMetrics.maxLanes }) { span in
                    let x = CGFloat(span.startColumn) * columnWidth + 2
                    let width = CGFloat(span.endColumn - span.startColumn + 1) * columnWidth - 4
                    let y = rowMetrics.dayNumberHeight + rowMetrics.chipTopInset
                        + CGFloat(span.lane) * (rowMetrics.chipHeight + rowMetrics.chipSpacing)

                    Button {
                        onSelectTask(span.task)
                    } label: {
                        MonthTaskChip(
                            title: span.showsTitle ? span.title : " ",
                            accent: span.task.cardHeaderAccentColor,
                            isDimmed: span.isDimmed,
                            isCompleted: span.task.status == .completed,
                            fontSize: rowMetrics.titleFontSize
                        )
                    }
                    .buttonStyle(.plain)
                    .taskLongPressContextMenu(
                        showsComplete: span.task.status != .completed
                            && span.task.status != .cancelled
                            && onTaskComplete != nil,
                        onEdit: { onSelectTask(span.task) },
                        onComplete: { onTaskComplete?(span.task) },
                        onDelete: { onTaskDelete?(span.task) }
                    )
                    .frame(width: max(8, width), height: rowMetrics.chipHeight, alignment: .leading)
                    .offset(x: x, y: y)
                }
            }
        }
    }

    private func dayBackgroundButton(cell: YearDayCellData, dayNumberHeight: CGFloat) -> some View {
        Button {
            guard let date = cell.date else { return }
            onSelectDay(date)
        } label: {
            VStack(spacing: 0) {
                HStack {
                    Text(dayNumberText(cell))
                        .font(.caption.weight(isSelected(cell) ? .bold : .semibold))
                        .foregroundStyle(dayNumberColor(cell))
                        .frame(minWidth: 22, minHeight: 18)
                        .padding(.horizontal, isSelected(cell) ? 5 : 0)
                        .background {
                            if isSelected(cell) {
                                Circle().fill(AppTheme.ColorToken.accent)
                            } else if cell.isToday {
                                Circle().stroke(AppTheme.ColorToken.accent, lineWidth: 1.5)
                            }
                        }
                        .padding(.top, 2)
                        .padding(.leading, 4)
                    Spacer(minLength: 0)
                }
                .frame(height: dayNumberHeight)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cell.date == nil)
    }

    private func dayNumberText(_ cell: YearDayCellData) -> String {
        guard cell.date != nil else { return "" }
        return "\(cell.dayNumber)"
    }

    private func isSelected(_ cell: YearDayCellData) -> Bool {
        guard let date = cell.date else { return false }
        return calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func dayNumberColor(_ cell: YearDayCellData) -> Color {
        if isSelected(cell) { return .white }
        if cell.isToday { return AppTheme.ColorToken.accent }
        if cell.isInMonth == false { return .secondary.opacity(0.45) }
        return .primary
    }
}

// MARK: - Chip

private struct MonthTaskChip: View {
    let title: String
    let accent: Color
    let isDimmed: Bool
    let isCompleted: Bool
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            if isCompleted {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: max(8, fontSize - 1), weight: .bold))
                    .foregroundStyle(accent.opacity(isDimmed ? 0.45 : 0.9))
            }
            Text(title)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(isDimmed ? 0.45 : 0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.leading, 5)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(accent.opacity(isDimmed ? 0.32 : 0.5))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent.opacity(isDimmed ? 0.45 : 0.95))
                .frame(width: 2.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

// MARK: - Grid lines

private struct MonthGridLines: View {
    let weekRowCount: Int

    var body: some View {
        Canvas { context, size in
            let stroke = Color.secondary.opacity(0.22)
            let columnWidth = size.width / 7
            let rowHeight = size.height / CGFloat(weekRowCount)

            for column in 0...7 {
                var path = Path()
                let x = CGFloat(column) * columnWidth
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(stroke), lineWidth: 0.5)
            }
            for row in 0...weekRowCount {
                var path = Path()
                let y = CGFloat(row) * rowHeight
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(stroke), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Span layout

private struct MonthWeekSpanItem: Identifiable {
    let id: String
    let task: FamilyTask
    let title: String
    let startColumn: Int
    let endColumn: Int
    let lane: Int
    let showsTitle: Bool
    let isDimmed: Bool
}

private enum MonthWeekSpanLayout {
    static func spans(
        weekCells: [YearDayCellData],
        tasks: [FamilyTask],
        calendar: Calendar,
        titleForTask: (FamilyTask) -> String
    ) -> [MonthWeekSpanItem] {
        guard weekCells.count == 7 else { return [] }
        let weekDates = weekCells.compactMap(\.date).map { calendar.startOfDay(for: $0) }
        guard let weekStart = weekDates.first, let weekEnd = weekDates.last else { return [] }

        var candidates: [(task: FamilyTask, startCol: Int, endCol: Int, title: String, dimmed: Bool)] = []

        for task in tasks {
            let range = visibleDayRange(for: task, calendar: calendar)
            guard range.start <= weekEnd, range.end >= weekStart else { continue }

            let clippedStart = max(range.start, weekStart)
            let clippedEnd = min(range.end, weekEnd)
            guard
                let startCol = columnIndex(of: clippedStart, in: weekCells, calendar: calendar),
                let endCol = columnIndex(of: clippedEnd, in: weekCells, calendar: calendar)
            else {
                continue
            }

            let dimmed = weekCells[startCol].isInMonth == false
            candidates.append(
                (
                    task: task,
                    startCol: startCol,
                    endCol: max(startCol, endCol),
                    title: titleForTask(task),
                    dimmed: dimmed
                )
            )
        }

        candidates.sort { lhs, rhs in
            let lhsSpan = lhs.endCol - lhs.startCol
            let rhsSpan = rhs.endCol - rhs.startCol
            if lhsSpan != rhsSpan { return lhsSpan > rhsSpan }
            if lhs.startCol != rhs.startCol { return lhs.startCol < rhs.startCol }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        var laneEnds: [Int] = []
        var result: [MonthWeekSpanItem] = []

        for item in candidates {
            var lane = 0
            while lane < laneEnds.count, laneEnds[lane] >= item.startCol {
                lane += 1
            }
            if lane == laneEnds.count {
                laneEnds.append(item.endCol)
            } else {
                laneEnds[lane] = item.endCol
            }

            result.append(
                MonthWeekSpanItem(
                    id: "\(item.task.id.uuidString)-\(item.startCol)-\(item.endCol)-\(lane)",
                    task: item.task,
                    title: item.title,
                    startColumn: item.startCol,
                    endColumn: item.endCol,
                    lane: lane,
                    showsTitle: true,
                    isDimmed: item.dimmed
                )
            )
        }

        return result
    }

    private static func visibleDayRange(
        for task: FamilyTask,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: task.scheduleStartDate)
        let endRaw = calendar.startOfDay(for: task.timelineEndDate)
        // 跨午夜但不足整天的定时任务：仍落在开始日一格。
        if calendar.isDate(start, inSameDayAs: endRaw) {
            return (start, start)
        }
        // end 落在结束日 00:00 时回退一天，避免多占一格。
        let endExclusive = task.timelineEndDate
        let endDay: Date
        if calendar.dateComponents([.hour, .minute, .second], from: endExclusive)
            == DateComponents(hour: 0, minute: 0, second: 0),
           endExclusive > task.scheduleStartDate,
           let previous = calendar.date(byAdding: .day, value: -1, to: endRaw) {
            endDay = previous
        } else {
            endDay = endRaw
        }
        return (start, max(start, endDay))
    }

    private static func columnIndex(
        of day: Date,
        in weekCells: [YearDayCellData],
        calendar: Calendar
    ) -> Int? {
        weekCells.firstIndex { cell in
            guard let date = cell.date else { return false }
            return calendar.isDate(date, inSameDayAs: day)
        }
    }
}

#Preview {
    TaskMonthView(
        selectedDate: .constant(Date()),
        tasks: [],
        titleForTask: { $0.title },
        onSelectDay: { _ in },
        onSelectTask: { _ in }
    )
}
