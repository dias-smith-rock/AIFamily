import Foundation

/// 年视图单日格子：在 ViewModel 预计算，视图层只做 O(1) 查表与绘制。
struct YearDayCellData: Hashable, Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let date: Date?
    let dayNumber: Int
    let isInMonth: Bool
    let isToday: Bool
}

/// 年视图单月矩阵：固定 42 格（6×7），避免在 SwiftUI body 中做 Calendar 运算。
struct YearMonthGridData: Hashable, Identifiable {
    let id: Int
    let month: Int
    let monthStart: Date
    let title: String
    let cells: [YearDayCellData]
}

/// 年视图整年快照：12 个月 + 任务密度字典。
struct YearCalendarSnapshot: Equatable {
    let year: Int
    let weekdaySymbols: [String]
    let months: [YearMonthGridData]
    let taskDensityByDayKey: [String: Int]
}

enum YearHeatmapMetrics {
    /// 热力底色不透明度：任务越多越深。
    static func fillOpacity(taskCount: Int) -> Double {
        switch taskCount {
        case 0:
            return 0
        case 1:
            return 0.2
        case 2:
            return 0.5
        default:
            return 0.8
        }
    }
}

enum YearCalendarBuilder {
    private static let posixCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = posixCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let normalized = calendar.startOfDay(for: date)
        return dayKeyFormatter.string(from: normalized)
    }

    /// 从已加载的日程任务聚合指定年份的 `[yyyy-MM-dd: count]`，供热力渲染 O(1) 查询。
    static func taskDensity(
        for year: Int,
        tasks: [FamilyTask],
        calendar: Calendar = .current,
        taskAnchor: (FamilyTask) -> Date
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(min(tasks.count, 366))

        for task in tasks {
            let anchor = calendar.startOfDay(for: taskAnchor(task))
            guard calendar.component(.year, from: anchor) == year else { continue }
            let key = dayKey(for: anchor, calendar: calendar)
            counts[key, default: 0] += 1
        }
        return counts
    }

    static func makeSnapshot(
        year: Int,
        locale: Locale,
        taskDensityByDayKey: [String: Int],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> YearCalendarSnapshot {
        var localizedCalendar = calendar
        localizedCalendar.locale = locale

        let weekdaySymbols = singleLetterWeekdaySymbols(calendar: localizedCalendar, locale: locale)
        let todayKey = dayKey(for: now, calendar: calendar)
        let months = (1...12).compactMap { month -> YearMonthGridData? in
            guard
                let monthStart = localizedCalendar.date(
                    from: DateComponents(year: year, month: month, day: 1)
                )
            else {
                return nil
            }
            let title = monthStart.formatted(
                .dateTime
                    .month(.abbreviated)
                    .locale(locale)
            )
            let cells = monthGridCells(
                monthStart: monthStart,
                calendar: localizedCalendar,
                todayKey: todayKey
            )
            return YearMonthGridData(
                id: month,
                month: month,
                monthStart: monthStart,
                title: title,
                cells: cells
            )
        }

        return YearCalendarSnapshot(
            year: year,
            weekdaySymbols: weekdaySymbols,
            months: months,
            taskDensityByDayKey: taskDensityByDayKey
        )
    }

    private static func singleLetterWeekdaySymbols(calendar: Calendar, locale: Locale) -> [String] {
        var calendar = calendar
        calendar.locale = locale
        return calendar.veryShortWeekdaySymbols.map { symbol in
            String(symbol.prefix(1)).uppercased()
        }
    }

    private static func monthGridCells(
        monthStart: Date,
        calendar: Calendar,
        todayKey: String
    ) -> [YearDayCellData] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthStart) else {
            return []
        }

        let firstDay = monthInterval.start
        let dayCount = calendar.dateComponents([.day], from: firstDay, to: monthInterval.end).day ?? 0
        let weekdayOfFirstDay = calendar.component(.weekday, from: firstDay)
        let leadingSlots = (weekdayOfFirstDay - calendar.firstWeekday + 7) % 7

        var cells: [YearDayCellData] = []
        cells.reserveCapacity(42)

        for _ in 0..<leadingSlots {
            cells.append(
                YearDayCellData(
                    dayKey: "pad-\(cells.count)",
                    date: nil,
                    dayNumber: 0,
                    isInMonth: false,
                    isToday: false
                )
            )
        }

        for dayOffset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) else {
                continue
            }
            let key = dayKey(for: date, calendar: calendar)
            cells.append(
                YearDayCellData(
                    dayKey: key,
                    date: date,
                    dayNumber: calendar.component(.day, from: date),
                    isInMonth: true,
                    isToday: key == todayKey
                )
            )
        }

        while cells.count < 42 {
            cells.append(
                YearDayCellData(
                    dayKey: "pad-\(cells.count)",
                    date: nil,
                    dayNumber: 0,
                    isInMonth: false,
                    isToday: false
                )
            )
        }

        return cells
    }
}
