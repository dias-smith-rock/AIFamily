import SwiftUI
import WidgetKit

struct ScheduleWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ScheduleWidgetSnapshot?
}

struct ScheduleWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleWidgetEntry {
        ScheduleWidgetEntry(date: Date(), snapshot: Self.placeholderSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleWidgetEntry) -> Void) {
        let snapshot = ScheduleWidgetSnapshotStore.load() ?? Self.placeholderSnapshot()
        completion(ScheduleWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = ScheduleWidgetSnapshotStore.load()
        let calendar = snapshot?.calendar ?? Calendar.current
        let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60 * 60)
        let entry = ScheduleWidgetEntry(date: now, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private static func placeholderSnapshot() -> ScheduleWidgetSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let parts = ScheduleWidgetLink.components(of: now, calendar: calendar)
        return ScheduleWidgetSnapshot(
            householdId: nil,
            generatedAt: now,
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: calendar.timeZone.identifier,
            tasks: [
                ScheduleWidgetTask(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                    title: String(localized: "widget_placeholder_task"),
                    year: parts.year,
                    month: parts.month,
                    day: parts.day,
                    isAllDay: true,
                    minutesFromMidnight: nil
                )
            ]
        )
    }
}

struct ScheduleWidgetView: View {
    var entry: ScheduleWidgetEntry

    private var snapshot: ScheduleWidgetSnapshot? { entry.snapshot }
    private var calendar: Calendar { snapshot?.calendar ?? .current }
    private var locale: Locale { snapshot?.locale ?? .current }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            dayColumn
                .frame(width: 128, alignment: .leading)
            monthColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(openURL(for: entry.date))
    }

    private var dayColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link(destination: openURL(for: entry.date)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.date, format: weekdayFormat)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.blue)
                        .textCase(.uppercase)
                    Text(entry.date, format: dayFormat)
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.8)
                    taskSummary
                }
            }
            Spacer(minLength: 0)
            Link(destination: createURL(for: entry.date)) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.blue, in: Circle())
            }
            .accessibilityLabel(Text("widget_create_task"))
        }
    }

    @ViewBuilder
    private var taskSummary: some View {
        let tasks = snapshot?.tasks(on: entry.date) ?? []
        let visible = Array(tasks.prefix(2))
        ForEach(visible) { task in
            taskChip(task.title)
        }
        if tasks.count > visible.count {
            Text(moreLabel(tasks.count - visible.count))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func taskChip(_ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue, in: Capsule())
    }

    private var monthColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date, format: monthFormat)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.blue)
                .textCase(.uppercase)
            monthGrid
        }
    }

    private var monthGrid: some View {
        let symbols = weekdaySymbols
        let cells = monthCells
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 1
        ) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            ForEach(cells) { cell in
                if let day = cell.day {
                    Link(destination: ScheduleWidgetLink.openDay(year: cell.year, month: cell.month, day: day)) {
                        dayNumber(cell)
                    }
                } else {
                    Color.clear.frame(height: 16)
                }
            }
        }
    }

    private func dayNumber(_ cell: MonthCell) -> some View {
        let isToday = cell.isToday
        let hasTask = cell.hasTask
        return VStack(spacing: 0) {
            Text("\(cell.day ?? 0)")
                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 15, height: 15)
                .background(isToday ? Color.blue : Color.clear, in: Circle())
            Circle()
                .fill(hasTask ? Color.blue : Color.clear)
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekdayFormat: Date.FormatStyle {
        Date.FormatStyle().weekday(.wide).locale(locale)
    }

    private var dayFormat: Date.FormatStyle {
        Date.FormatStyle().day().locale(locale)
    }

    private var monthFormat: Date.FormatStyle {
        Date.FormatStyle().month(.wide).locale(locale)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(0, calendar.firstWeekday - 1)
        return Array(symbols[start...]) + Array(symbols[..<start])
    }

    private var monthCells: [MonthCell] {
        guard let interval = calendar.dateInterval(of: .month, for: entry.date),
              let dayCount = calendar.range(of: .day, in: .month, for: entry.date)?.count else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let year = calendar.component(.year, from: entry.date)
        let month = calendar.component(.month, from: entry.date)
        let today = ScheduleWidgetLink.components(of: entry.date, calendar: calendar)
        var cells: [MonthCell] = []
        for index in 0..<leading {
            cells.append(MonthCell(index: index, year: year, month: month, day: nil, isToday: false, hasTask: false))
        }
        for day in 1...dayCount {
            cells.append(
                MonthCell(
                    index: leading + day,
                    year: year,
                    month: month,
                    day: day,
                    isToday: today.year == year && today.month == month && today.day == day,
                    hasTask: snapshot?.hasTask(year: year, month: month, day: day) ?? false
                )
            )
        }
        return cells
    }

    private func openURL(for date: Date) -> URL {
        let parts = ScheduleWidgetLink.components(of: date, calendar: calendar)
        return ScheduleWidgetLink.openDay(year: parts.year, month: parts.month, day: parts.day)
    }

    private func createURL(for date: Date) -> URL {
        let parts = ScheduleWidgetLink.components(of: date, calendar: calendar)
        return ScheduleWidgetLink.createTask(year: parts.year, month: parts.month, day: parts.day)
    }

    private func moreLabel(_ count: Int) -> String {
        let format = String(localized: String.LocalizationValue("widget_more_count"), locale: locale)
        return String(format: format, locale: locale, count)
    }
}

private struct MonthCell: Identifiable {
    let index: Int
    let year: Int
    let month: Int
    let day: Int?
    let isToday: Bool
    let hasTask: Bool

    var id: Int { index }
}

struct ScheduleCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ScheduleWidgetKind.calendar, provider: ScheduleWidgetProvider()) { entry in
            ScheduleWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("widget_display_name")
        .description("widget_description")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScheduleCalendarWidget()
    }
}
