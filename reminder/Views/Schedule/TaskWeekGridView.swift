import SwiftUI

/// Week 模式：7 日 × 24 小时时间网格（由 `TaskListView` 嵌入）。
struct TaskWeekGridView: View {
    @Environment(\.locale) private var locale

    @ObservedObject var viewModel: ScheduleViewModel
    @Binding var selectedDate: Date

    let onTaskSelect: (FamilyTask) -> Void
    let onRefresh: (() async -> Void)?

    @State private var weekEpochStart: Date = ScheduleWeekCalendar.startOfWeek(for: Date())
    @State private var weekOffset: Int = 0
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
            weekOffset = ScheduleWeekCalendar.weekOffset(
                for: selectedDate,
                epochStart: weekEpochStart
            )
        }
        .onChange(of: selectedDate) { _, newValue in
            let target = ScheduleWeekCalendar.weekOffset(
                for: newValue,
                epochStart: weekEpochStart
            )
            if weekOffset != target {
                withAnimation(.easeInOut(duration: 0.25)) {
                    weekOffset = target
                }
            }
        }
    }

    // MARK: - Week pager

    /// 与日视图一致：周头固定 84pt 的 `TabView`，下方为全天条 + 网格（避免整页 `TabView` 垂直居中产生大块空白）。
    private var weekPager: some View {
        VStack(alignment: .leading, spacing: 10) {
            weekHeaderSection

            TabView(selection: $weekOffset) {
                ForEach(ScheduleWeekCalendar.weekPageRange, id: \.self) { offset in
                    weekBody(for: offset)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var weekHeaderSection: some View {
        TabView(selection: $weekOffset) {
            ForEach(ScheduleWeekCalendar.weekPageRange, id: \.self) { offset in
                let days = ScheduleWeekCalendar.daysInWeek(
                    weekOffset: offset,
                    epochStart: weekEpochStart
                )
                let weekTasks = tasks(in: days)
                weekHeaderRow(days: days, weekTasks: weekTasks)
                    .padding(.horizontal, horizontalPadding)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 84, alignment: .top)
    }

    private func weekBody(for offset: Int) -> some View {
        let days = ScheduleWeekCalendar.daysInWeek(
            weekOffset: offset,
            epochStart: weekEpochStart
        )
        let weekTasks = tasks(in: days)

        return VStack(alignment: .leading, spacing: 10) {
            if hasAllDayTasks(in: weekTasks, days: days) {
                allDayStrip(days: days, weekTasks: weekTasks)
                    .padding(.horizontal, horizontalPadding)
            }

            ZStack(alignment: .bottomTrailing) {
                timelineScrollArea(
                    days: days,
                    weekTasks: weekTasks
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

    private func timelineScrollArea(days: [Date], weekTasks: [FamilyTask]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    timeLabelsColumn
                        .frame(width: ScheduleTimelineMetrics.timeColumnWidth)

                    GeometryReader { geometry in
                        let gridWidth = geometry.size.width
                        let columnWidth = gridWidth / 7
                        let layoutItems = WeekTaskLayoutEngine.layout(
                            tasks: weekTasks,
                            weekDays: days,
                            columnWidth: columnWidth,
                            taskStart: taskDisplayDate,
                            taskEnd: { $0.timelineEndDate }
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
                                    .id(WeekGridScrollIDs.timeAnchor)
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
                scrollToInitialTime(proxy: proxy, days: days, animated: false)
            }
            .onChange(of: weekOffset) { _, _ in
                scrollToInitialTime(proxy: proxy, days: days, animated: true)
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
        withAnimation(.easeInOut(duration: 0.25)) {
            weekOffset = targetOffset
            selectedDate = today
        }
    }

    // MARK: - Task filtering

    private func tasks(in days: [Date]) -> [FamilyTask] {
        guard let first = days.first, let last = days.last else { return [] }
        let cal = Calendar.current
        let weekStart = cal.startOfDay(for: first)
        let weekEnd = cal.startOfDay(for: last)
        return viewModel.scheduledTasks.filter { task in
            let day = cal.startOfDay(for: taskDisplayDate(task))
            return day >= weekStart && day <= weekEnd
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

    private func scrollToInitialTime(proxy: ScrollViewProxy, days: [Date], animated: Bool) {
        guard days.contains(where: { Calendar.current.isDateInToday($0) }) else { return }
        let action = {
            proxy.scrollTo(WeekGridScrollIDs.timeAnchor, anchor: .top)
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
        Canvas { context, size in
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
    static let timeAnchor = "week-grid-time-anchor"
}

#Preview {
    TaskWeekGridView(
        selectedDate: .constant(Date()),
        viewModel: AppViewModels.makeScheduleViewModel(),
        onTaskSelect: { _ in }
    )
}
