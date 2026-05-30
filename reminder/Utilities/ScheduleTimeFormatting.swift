import Foundation

/// 日程 Tab 时间展示：固定 24 小时制，避免「上午/下午」与 AM/PM 文案。
enum ScheduleTimeFormatting {
    static func timelineClockTime(_ date: Date, locale: Locale = .current) -> String {
        date.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .locale(locale)
        )
    }
}
