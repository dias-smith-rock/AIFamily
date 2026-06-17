import Foundation

/// 自然周计算（与 `TaskModeDayView` 周条逻辑一致，供周视图复用）。
enum ScheduleWeekCalendar {
    /// 周视图侧滑分页窗口：上一周 / 当前周 / 下一周。
    static let pagerSlotCount = 3
    static let pagerCenterSlot = 1

    /// 日视图周条仍使用的历史页范围（周视图网格已改用三页窗口）。
    static let weekPageRange = -500...500

    static func startOfWeek(for date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let firstWeekday = calendar.firstWeekday
        let delta = (weekday - firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -delta, to: day) ?? day
    }

    static func daysInWeek(weekStart: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: weekStart)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func daysInWeek(
        weekOffset: Int,
        epochStart: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let weekStart = weekStart(forOffset: weekOffset, epochStart: epochStart, calendar: calendar)
        return daysInWeek(weekStart: weekStart, calendar: calendar)
    }

    static func weekStart(
        forOffset offset: Int,
        epochStart: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .day, value: offset * 7, to: epochStart) ?? epochStart
    }

    static func weekOffset(
        for date: Date,
        epochStart: Date,
        calendar: Calendar = .current
    ) -> Int {
        let targetWeekStart = startOfWeek(for: date, calendar: calendar)
        let days = calendar.dateComponents([.day], from: epochStart, to: targetWeekStart).day ?? 0
        return days / 7
    }
}
