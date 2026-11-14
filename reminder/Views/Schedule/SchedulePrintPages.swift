import SwiftUI
import UIKit

/// 按当前日程视图排版的打印页：周视图是七行任务卡，月视图是月历，日视图是周条加时间轴，列表按日分组。
struct SchedulePrintContext {
    let jobName: String
    let householdName: String
    let tasks: [FamilyTask]
    let calendar: Calendar
    let locale: Locale
    let selectedDate: Date
    let displayTitle: (FamilyTask) -> String
    let avatars: (FamilyTask) -> [TaskCardAvatarSource]
    let assigneeLabel: (FamilyTask) -> String
    let hasAttachments: (FamilyTask) -> Bool
    let delivery: FamilyPrintDelivery
}

@MainActor
enum SchedulePrintComposer {
    static func printWeek(_ context: SchedulePrintContext) {
        let days = ScheduleWeekCalendar.daysInWeek(
            weekStart: ScheduleWeekCalendar.startOfWeek(for: context.selectedDate, calendar: context.calendar),
            calendar: context.calendar
        )
        let grouped = days.map { day in
            (day, tasks(on: day, context: context))
        }
        let pages = pack(grouped, limit: 700) { pair in
            weekRowHeight(taskCount: pair.1.count)
        }
        let title = weekTitle(days: days, locale: context.locale)
        let images = pages.enumerated().map { index, slice in
            render(
                ScheduleWeekPrintPage(
                    title: title,
                    householdName: context.householdName,
                    days: slice,
                    calendar: context.calendar,
                    locale: context.locale,
                    titleForTask: context.displayTitle
                ),
                locale: context.locale
            )
        }
        present(context, images: images)
    }

    static func printMonth(_ context: SchedulePrintContext) {
        let monthStart = context.calendar.date(
            from: context.calendar.dateComponents([.year, .month], from: context.selectedDate)
        ) ?? context.selectedDate
        let image = render(
            ScheduleMonthPrintPage(
                monthStart: monthStart,
                selectedDate: context.selectedDate,
                tasks: context.tasks,
                calendar: context.calendar,
                locale: context.locale,
                titleForTask: context.displayTitle
            ),
            locale: context.locale
        )
        present(context, images: [image])
    }

    static func printDay(_ context: SchedulePrintContext) {
        let calendar = context.calendar
        let day = calendar.startOfDay(for: context.selectedDate)
        let dayTasks = tasks(on: day, context: context)
        let allDay = dayTasks.filter(\.isAllDay)
        let timed = dayTasks.filter { $0.isAllDay == false }
        let weekDays = ScheduleWeekCalendar.daysInWeek(
            weekStart: ScheduleWeekCalendar.startOfWeek(for: day, calendar: calendar),
            calendar: calendar
        )
        let counts = Dictionary(grouping: context.tasks) {
            $0.scheduleDisplayDay(displayCalendar: calendar)
        }.mapValues(\.count)
        let slices = dayPageSlices(
            day: day,
            weekDays: weekDays,
            taskCounts: counts,
            allDay: allDay,
            timed: timed,
            context: context
        )
        let pageCount = max(slices.count, 1)
        let images = (0..<pageCount).map { index in
            let slice = slices.indices.contains(index) ? slices[index] : []
            return render(
                ScheduleDayPrintPage(
                    showsChrome: index == 0,
                    day: day,
                    weekDays: weekDays,
                    taskCounts: counts,
                    allDay: index == 0 ? allDay : [],
                    timed: slice,
                    calendar: calendar,
                    locale: context.locale,
                    titleForTask: context.displayTitle,
                    avatars: context.avatars,
                    assigneeLabel: context.assigneeLabel,
                    hasAttachments: context.hasAttachments
                ),
                locale: context.locale
            )
        }
        present(context, images: images)
    }

    static func printList(_ context: SchedulePrintContext) {
        let calendar = context.calendar
        let grouped = Dictionary(grouping: context.tasks) { task in
            calendar.startOfDay(for: task.dueDate ?? task.originalDueDate ?? task.createdAt)
        }
        let days = grouped.keys.sorted()
        var rows: [ScheduleListPrintRow] = []
        for day in days {
            rows.append(.header(day))
            let tasks = (grouped[day] ?? []).sorted {
                ($0.dueDate ?? $0.originalDueDate ?? $0.createdAt)
                    < ($1.dueDate ?? $1.originalDueDate ?? $1.createdAt)
            }
            rows.append(contentsOf: tasks.map { .task($0) })
        }
        let packed = pack(rows, limit: 740) { row in
            switch row {
            case .header: return 52
            case .task: return 78
            }
        }
        var pages: [[ScheduleListPrintRow]] = []
        var carriedHeader: ScheduleListPrintRow?
        for page in packed {
            var slice = page
            if let pendingHeader = carriedHeader {
                slice.insert(pendingHeader, at: 0)
                carriedHeader = nil
            }
            if slice.count > 1, case .header = slice.last {
                carriedHeader = slice.removeLast()
            }
            if slice.isEmpty == false {
                pages.append(slice)
            }
        }
        if let pendingHeader = carriedHeader {
            pages.append([pendingHeader])
        }
        if pages.isEmpty {
            pages = [[]]
        }
        let images = pages.map { slice in
            render(
                ScheduleListPrintPage(
                    householdName: context.householdName,
                    rows: slice,
                    locale: context.locale,
                    titleForTask: context.displayTitle,
                    avatars: context.avatars,
                    accent: { $0.cardThemeAccentColor }
                ),
                locale: context.locale
            )
        }
        present(context, images: images)
    }

    static func printYear(_ context: SchedulePrintContext, snapshot: YearCalendarSnapshot?) {
        let image = render(
            ScheduleYearPrintPage(
                year: context.calendar.component(.year, from: context.selectedDate),
                snapshot: snapshot,
                selectedDayKey: YearCalendarBuilder.dayKey(for: context.selectedDate, calendar: context.calendar)
            ),
            locale: context.locale
        )
        present(context, images: [image])
    }

    private static func present(_ context: SchedulePrintContext, images: [UIImage]) {
        FamilyDocumentPrinter.deliver(
            jobName: context.jobName,
            images: images,
            delivery: context.delivery
        )
    }

    /// 整页内容不超过纸高时保持一页；超出后再按实测行高拆页。
    private static func dayPageSlices(
        day: Date,
        weekDays: [Date],
        taskCounts: [Date: Int],
        allDay: [FamilyTask],
        timed: [FamilyTask],
        context: SchedulePrintContext
    ) -> [[FamilyTask]] {
        let fitted = dayPage(
            day: day,
            weekDays: weekDays,
            taskCounts: taskCounts,
            allDay: allDay,
            timed: timed,
            context: context,
            showsChrome: true
        )
        let height = contentHeight(of: fitted, locale: context.locale)
        if height > 0, height <= SchedulePrintMetrics.page.height {
            return [timed]
        }
        if height == 0 {
            return pack(timed, firstLimit: 520, laterLimit: 700, itemHeight: 64)
        }

        let chrome = contentHeight(
            of: dayPage(
                day: day,
                weekDays: weekDays,
                taskCounts: taskCounts,
                allDay: allDay,
                timed: [],
                context: context,
                showsChrome: true
            ),
            locale: context.locale
        )
        let continuation = contentHeight(
            of: dayPage(
                day: day,
                weekDays: weekDays,
                taskCounts: taskCounts,
                allDay: [],
                timed: [],
                context: context,
                showsChrome: false
            ),
            locale: context.locale
        )
        let rowHeights = timed.map { task in
            contentHeight(
                of: ScheduleDayPrintTaskRow(
                    task: task,
                    locale: context.locale,
                    title: context.displayTitle(task),
                    avatars: context.avatars(task),
                    assigneeLabel: context.assigneeLabel(task),
                    hasAttachments: context.hasAttachments(task)
                )
                .padding(.horizontal, 28),
                locale: context.locale
            ) + 12
        }
        return packMeasured(
            timed,
            heights: rowHeights,
            firstUsed: chrome,
            laterUsed: continuation,
            limit: SchedulePrintMetrics.page.height
        )
    }

    private static func dayPage(
        day: Date,
        weekDays: [Date],
        taskCounts: [Date: Int],
        allDay: [FamilyTask],
        timed: [FamilyTask],
        context: SchedulePrintContext,
        showsChrome: Bool
    ) -> ScheduleDayPrintPage {
        ScheduleDayPrintPage(
            showsChrome: showsChrome,
            day: day,
            weekDays: weekDays,
            taskCounts: taskCounts,
            allDay: allDay,
            timed: timed,
            calendar: context.calendar,
            locale: context.locale,
            titleForTask: context.displayTitle,
            avatars: context.avatars,
            assigneeLabel: context.assigneeLabel,
            hasAttachments: context.hasAttachments,
            fillsPage: false
        )
    }

    private static func packMeasured<Item>(
        _ items: [Item],
        heights: [CGFloat],
        firstUsed: CGFloat,
        laterUsed: CGFloat,
        limit: CGFloat
    ) -> [[Item]] {
        guard items.isEmpty == false else { return [[]] }
        var pages: [[Item]] = [[]]
        var used = firstUsed
        for (item, rawHeight) in zip(items, heights) {
            let rowHeight = rawHeight.isFinite && rawHeight > 0 ? rawHeight : 72
            if pages[pages.count - 1].isEmpty == false, used + rowHeight > limit {
                pages.append([])
                used = laterUsed
            }
            pages[pages.count - 1].append(item)
            used += rowHeight
        }
        return pages.filter { $0.isEmpty == false }
    }

    private static func contentHeight<V: View>(of view: V, locale: Locale) -> CGFloat {
        let root = view
            .frame(width: SchedulePrintMetrics.page.width, alignment: .topLeading)
            .environment(\.colorScheme, .light)
            .environment(\.locale, locale)
        let host = UIHostingController(rootView: root)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        let size = host.sizeThatFits(
            in: CGSize(width: SchedulePrintMetrics.page.width, height: 10_000)
        )
        guard size.height.isFinite, size.height > 0, size.height < 9_000 else { return 0 }
        return size.height
    }

    private static func render<V: View>(_ page: V, locale: Locale) -> UIImage {
        let canvas = page
            .frame(
                width: SchedulePrintMetrics.page.width,
                height: SchedulePrintMetrics.page.height,
                alignment: .top
            )
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, locale)
        let renderer = ImageRenderer(content: canvas)
        renderer.proposedSize = ProposedViewSize(
            width: SchedulePrintMetrics.page.width,
            height: SchedulePrintMetrics.page.height
        )
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage ?? UIImage()
    }

    private static func tasks(on day: Date, context: SchedulePrintContext) -> [FamilyTask] {
        context.tasks
            .filter {
                context.calendar.isDate(
                    $0.scheduleDisplayDay(displayCalendar: context.calendar),
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

    private static func weekTitle(days: [Date], locale: Locale) -> String {
        let start = (days.first ?? Date()).formatted(.dateTime.month(.abbreviated).day().locale(locale))
        let end = (days.last ?? Date()).formatted(.dateTime.month(.abbreviated).day().locale(locale))
        return "\(start) – \(end)"
    }

    private static func weekRowHeight(taskCount: Int) -> CGFloat {
        let rows = taskCount == 0 ? 1 : wrapRowCount(itemCount: taskCount, cardWidth: SchedulePrintMetrics.weekCard.width, rowWidth: SchedulePrintMetrics.weekCardRowWidth)
        return 8 + CGFloat(rows) * SchedulePrintMetrics.weekCard.height
            + CGFloat(max(0, rows - 1)) * SchedulePrintMetrics.cardSpacing
    }

    private static func wrapRowCount(itemCount: Int, cardWidth: CGFloat, rowWidth: CGFloat) -> Int {
        let perRow = max(1, Int((rowWidth + SchedulePrintMetrics.cardSpacing) / (cardWidth + SchedulePrintMetrics.cardSpacing)))
        return Int(ceil(Double(max(itemCount, 1)) / Double(perRow)))
    }

    private static func wrapHeight(itemCount: Int, cardWidth: CGFloat, cardHeight: CGFloat, rowWidth: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let rows = wrapRowCount(itemCount: itemCount, cardWidth: cardWidth, rowWidth: rowWidth)
        return CGFloat(rows) * cardHeight + CGFloat(max(0, rows - 1)) * SchedulePrintMetrics.cardSpacing
    }

    private static func pack<Item>(_ items: [Item], limit: CGFloat, height: (Item) -> CGFloat) -> [[Item]] {
        pack(items, firstLimit: limit, laterLimit: limit, height: height)
    }

    private static func pack<Item>(
        _ items: [Item],
        firstLimit: CGFloat,
        laterLimit: CGFloat,
        itemHeight: CGFloat
    ) -> [[Item]] {
        pack(items, firstLimit: firstLimit, laterLimit: laterLimit) { _ in itemHeight }
    }

    private static func pack<Item>(
        _ items: [Item],
        firstLimit: CGFloat,
        laterLimit: CGFloat,
        height: (Item) -> CGFloat
    ) -> [[Item]] {
        guard items.isEmpty == false else { return [] }
        var pages: [[Item]] = []
        var page: [Item] = []
        var used: CGFloat = 0
        for item in items {
            let itemHeight = max(1, height(item))
            let limit = pages.isEmpty ? firstLimit : laterLimit
            if used > 0, used + itemHeight > limit {
                pages.append(page)
                page = []
                used = 0
            }
            page.append(item)
            used += itemHeight
        }
        if page.isEmpty == false {
            pages.append(page)
        }
        return pages
    }
}

private enum SchedulePrintMetrics {
    static let page = CGSize(width: 595, height: 842)
    static let weekCard = CGSize(width: 108, height: 62)
    static let cardSpacing: CGFloat = 6
    static var weekCardRowWidth: CGFloat {
        page.width - 56 - 44 - 12
    }

    /// ImageRenderer 测量时会传入无限宽度，直接转 Int 会崩溃。
    static func finite(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : fallback
    }
}

private struct PrintCardWrapLayout: Layout {
    var cardWidth: CGFloat
    var cardHeight: CGFloat
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = SchedulePrintMetrics.finite(
            proposal.width ?? SchedulePrintMetrics.weekCardRowWidth,
            fallback: SchedulePrintMetrics.weekCardRowWidth
        )
        let perRow = cardsPerRow(in: width)
        let rows = Int(ceil(Double(max(subviews.count, 1)) / Double(perRow)))
        let height = CGFloat(rows) * cardHeight + CGFloat(max(0, rows - 1)) * spacing
        return CGSize(width: width, height: subviews.isEmpty ? cardHeight : height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let perRow = cardsPerRow(in: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let row = index / perRow
            let column = index % perRow
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(column) * (cardWidth + spacing),
                    y: bounds.minY + CGFloat(row) * (cardHeight + spacing)
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: cardWidth, height: cardHeight)
            )
        }
    }

    private func cardsPerRow(in width: CGFloat) -> Int {
        let available = SchedulePrintMetrics.finite(width, fallback: SchedulePrintMetrics.weekCardRowWidth)
        let stride = SchedulePrintMetrics.finite(cardWidth + spacing, fallback: cardWidth)
        return max(1, Int(available / stride))
    }
}

// MARK: - Week

private struct ScheduleWeekPrintPage: View {
    let title: String
    let householdName: String
    let days: [(Date, [FamilyTask])]
    let calendar: Calendar
    let locale: Locale
    let titleForTask: (FamilyTask) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(householdName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            ForEach(Array(days.enumerated()), id: \.offset) { index, pair in
                weekRow(day: pair.0, tasks: pair.1)
                if index < days.count - 1 {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func weekRow(day: Date, tasks: [FamilyTask]) -> some View {
        let isToday = calendar.isDateInToday(day)
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isToday ? AppTheme.ColorToken.accent : .secondary)
                Text("\(calendar.component(.day, from: day))")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isToday ? AppTheme.ColorToken.accent : .primary)
            }
            .frame(width: 44)
            .padding(.top, 8)

            if tasks.isEmpty {
                Color.clear.frame(height: SchedulePrintMetrics.weekCard.height)
            } else {
                PrintCardWrapLayout(
                    cardWidth: SchedulePrintMetrics.weekCard.width,
                    cardHeight: SchedulePrintMetrics.weekCard.height,
                    spacing: SchedulePrintMetrics.cardSpacing
                ) {
                    ForEach(tasks) { task in
                        SchedulePrintWeekCard(
                            title: titleForTask(task),
                            meta: meta(for: task),
                            accent: task.cardHeaderAccentColor
                        )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func meta(for task: FamilyTask) -> String {
        if task.isAllDay {
            return L10n.Common.allDay.string(locale: locale)
        }
        return ScheduleTimeFormatting.timelineClockTime(task.scheduleStartDate, locale: locale)
    }
}

private struct SchedulePrintWeekCard: View {
    let title: String
    let meta: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(meta)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(accent.opacity(0.46))
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
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Month

private struct ScheduleMonthPrintPage: View {
    let monthStart: Date
    let selectedDate: Date
    let tasks: [FamilyTask]
    let calendar: Calendar
    let locale: Locale
    let titleForTask: (FamilyTask) -> String

    private var weeks: [[YearDayCellData]] {
        let cells = YearCalendarBuilder.monthGridCells(monthStart: monthStart, calendar: calendar)
        let raw = stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
        return raw.filter { week in week.contains(where: \.isInMonth) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthStart.formatted(.dateTime.month(.wide).year().locale(locale)))
                .font(.title.weight(.bold))

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent.opacity(0.75))
                        .frame(maxWidth: .infinity)
                }
            }

            GeometryReader { geometry in
                let rowHeight = geometry.size.height / CGFloat(max(weeks.count, 1))
                VStack(spacing: 0) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        monthWeekRow(week, rowHeight: rowHeight, width: geometry.size.width)
                            .frame(height: rowHeight)
                    }
                }
                .overlay {
                    MonthPrintGridLines(weekRowCount: max(weeks.count, 1))
                }
            }
            .frame(height: 700)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        guard first > 0, first < symbols.count else { return symbols }
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private func monthWeekRow(_ week: [YearDayCellData], rowHeight: CGFloat, width: CGFloat) -> some View {
        let spans = MonthWeekSpanLayout.spans(
            weekCells: week,
            tasks: tasks,
            calendar: calendar,
            titleForTask: titleForTask
        )
        let dayNumberHeight: CGFloat = 22
        let chipHeight: CGFloat = 16
        let chipSpacing: CGFloat = 3
        let usable = SchedulePrintMetrics.finite(max(0, rowHeight - dayNumberHeight - 6), fallback: chipHeight)
        let maxLanes = max(1, Int(floor((usable + chipSpacing) / (chipHeight + chipSpacing))))
        let columnWidth = SchedulePrintMetrics.finite(width, fallback: SchedulePrintMetrics.page.width) / 7
        let hiddenByColumn = overflowCount(spans: spans, maxLanes: maxLanes)

        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(week) { cell in
                    dayNumber(cell)
                        .frame(width: columnWidth, height: rowHeight, alignment: .topLeading)
                }
            }
            ForEach(spans.filter { $0.lane < maxLanes }) { span in
                let x = CGFloat(span.startColumn) * columnWidth + 2
                let chipWidth = CGFloat(span.endColumn - span.startColumn + 1) * columnWidth - 4
                let y = dayNumberHeight + CGFloat(span.lane) * (chipHeight + chipSpacing)
                SchedulePrintMonthChip(
                    title: span.showsTitle ? span.title : " ",
                    accent: span.task.cardHeaderAccentColor,
                    isDimmed: span.isDimmed,
                    isCompleted: span.task.status == .completed
                )
                .frame(width: max(8, chipWidth), height: chipHeight)
                .offset(x: x, y: y)
            }
            ForEach(0..<7, id: \.self) { column in
                if let extra = hiddenByColumn[column], extra > 0 {
                    Text("+\(extra)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .offset(x: CGFloat(column) * columnWidth + 4, y: rowHeight - 12)
                }
            }
        }
    }

    private func overflowCount(spans: [MonthWeekSpanItem], maxLanes: Int) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for span in spans where span.lane >= maxLanes {
            for column in span.startColumn...span.endColumn {
                counts[column, default: 0] += 1
            }
        }
        return counts
    }

    private func dayNumber(_ cell: YearDayCellData) -> some View {
        let selected = cell.date.map { calendar.isDate($0, inSameDayAs: selectedDate) } ?? false
        return Text(cell.date == nil ? "" : "\(cell.dayNumber)")
            .font(.caption.weight(selected || cell.isToday ? .bold : .semibold))
            .foregroundStyle(dayNumberColor(cell, selected: selected))
            .frame(minWidth: 18, minHeight: 18)
            .background {
                if selected {
                    Circle().fill(AppTheme.ColorToken.accent)
                } else if cell.isToday {
                    Circle().stroke(AppTheme.ColorToken.accent, lineWidth: 1.5)
                }
            }
            .padding(.top, 2)
            .padding(.leading, 4)
    }

    private func dayNumberColor(_ cell: YearDayCellData, selected: Bool) -> Color {
        if selected { return .white }
        if cell.isToday { return AppTheme.ColorToken.accent }
        if cell.isInMonth == false { return .secondary.opacity(0.45) }
        return .primary
    }
}

private struct SchedulePrintMonthChip: View {
    let title: String
    let accent: Color
    let isDimmed: Bool
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 3) {
            if isCompleted {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.primary.opacity(isDimmed ? 0.45 : 0.9))
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

private struct MonthPrintGridLines: View {
    let weekRowCount: Int

    var body: some View {
        Canvas { context, size in
            let stroke = Color.secondary.opacity(0.28)
            let columnWidth = size.width / 7
            let rowHeight = size.height / CGFloat(max(weekRowCount, 1))
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

// MARK: - Day

private struct ScheduleDayPrintPage: View {
    let showsChrome: Bool
    let day: Date
    let weekDays: [Date]
    let taskCounts: [Date: Int]
    let allDay: [FamilyTask]
    let timed: [FamilyTask]
    let calendar: Calendar
    let locale: Locale
    let titleForTask: (FamilyTask) -> String
    let avatars: (FamilyTask) -> [TaskCardAvatarSource]
    let assigneeLabel: (FamilyTask) -> String
    let hasAttachments: (FamilyTask) -> Bool
    var fillsPage: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsChrome {
                Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(locale)))
                    .font(.title2.weight(.bold))
                HStack(spacing: 0) {
                    ForEach(weekDays, id: \.self) { date in
                        ScheduleWeekDayStripCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: day),
                            taskCount: taskCounts[calendar.startOfDay(for: date), default: 0],
                            locale: locale,
                            calendar: calendar
                        ) {}
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 72)
                if allDay.isEmpty == false {
                    PrintCardWrapLayout(cardWidth: 150, cardHeight: 36, spacing: 6) {
                        ForEach(allDay) { task in
                            SchedulePrintWeekCard(
                                title: titleForTask(task),
                                meta: L10n.Common.allDay.string(locale: locale),
                                accent: task.cardHeaderAccentColor
                            )
                        }
                    }
                }
            }

            ForEach(timed) { task in
                ScheduleDayPrintTaskRow(
                    task: task,
                    locale: locale,
                    title: titleForTask(task),
                    avatars: avatars(task),
                    assigneeLabel: assigneeLabel(task),
                    hasAttachments: hasAttachments(task)
                )
            }
            if fillsPage {
                Spacer(minLength: 0)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: fillsPage ? .infinity : nil, alignment: .top)
    }
}

private struct ScheduleDayPrintTaskRow: View {
    let task: FamilyTask
    let locale: Locale
    let title: String
    let avatars: [TaskCardAvatarSource]
    let assigneeLabel: String
    let hasAttachments: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(ScheduleTimeFormatting.timelineClockTime(task.scheduleStartDate, locale: locale))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
                .padding(.top, 12)
            TaskCardView(
                task: task,
                displayTitle: title,
                forWhomAvatars: avatars,
                assigneeLabel: assigneeLabel,
                hasAttachments: hasAttachments
            )
        }
    }
}

// MARK: - List

private enum ScheduleListPrintRow {
    case header(Date)
    case task(FamilyTask)
}

private struct ScheduleListPrintPage: View {
    let householdName: String
    let rows: [ScheduleListPrintRow]
    let locale: Locale
    let titleForTask: (FamilyTask) -> String
    let avatars: (FamilyTask) -> [TaskCardAvatarSource]
    let accent: (FamilyTask) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rows.isEmpty {
                Text(householdName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.Common.nothingToPrint.string(locale: locale))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Text(householdName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case .header(let day):
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(day.formatted(.dateTime.day().locale(locale)))
                                .font(.system(size: 32, weight: .bold))
                            Text(day.formatted(.dateTime.weekday(.wide).locale(locale)))
                                .font(.title3.weight(.bold))
                        }
                        .padding(.top, 6)
                    case .task(let task):
                        listRow(task)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func listRow(_ task: FamilyTask) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.status == .completed ? "✅ \(titleForTask(task))" : titleForTask(task))
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(timeLabel(task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TaskCardAssigneeTrailing(
                forWhomAvatars: avatars(task),
                style: .compact,
                accentColor: accent(task)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .taskCardSurface(for: task, cornerRadius: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.taskCardStroke(for: .light), lineWidth: 1)
        )
    }

    private func timeLabel(_ task: FamilyTask) -> String {
        if task.isAllDay {
            return L10n.Common.allDay.string(locale: locale)
        }
        return ScheduleTimeFormatting.timelineClockRange(
            start: task.scheduleStartDate,
            end: task.timelineEndDate,
            locale: locale
        )
    }
}

// MARK: - Year

private struct ScheduleYearPrintPage: View {
    let year: Int
    let snapshot: YearCalendarSnapshot?
    let selectedDayKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "\(snapshot?.year ?? year)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            if let snapshot {
                let rows = stride(from: 0, to: snapshot.months.count, by: 3).map { start in
                    Array(snapshot.months[start..<min(start + 3, snapshot.months.count)])
                }
                VStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(row) { month in
                                yearMonth(month, snapshot: snapshot)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func yearMonth(_ month: YearMonthGridData, snapshot: YearCalendarSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(month.title)
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 0) {
                ForEach(Array(snapshot.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            let weeks = stride(from: 0, to: month.cells.count, by: 7).map { start in
                Array(month.cells[start..<min(start + 7, month.cells.count)])
            }
            VStack(spacing: 1) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(week) { cell in
                            yearDay(cell, density: snapshot.taskDensityByDayKey[cell.dayKey] ?? 0)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(AppTheme.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.ColorToken.border, lineWidth: 0.5)
        }
    }

    private func yearDay(_ cell: YearDayCellData, density: Int) -> some View {
        ZStack {
            if cell.isInMonth, density > 0 {
                Circle()
                    .fill(AppTheme.ColorToken.accent.opacity(YearHeatmapMetrics.fillOpacity(taskCount: density)))
                    .frame(width: 16, height: 16)
            }
            if cell.isInMonth {
                Text("\(cell.dayNumber)")
                    .font(.system(size: 8, weight: cell.isToday ? .bold : .regular))
                    .foregroundStyle(cell.isToday ? AppTheme.ColorToken.accent : .primary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 16)
        .overlay {
            if cell.dayKey == selectedDayKey {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AppTheme.ColorToken.accent, lineWidth: 1)
            }
        }
    }
}
