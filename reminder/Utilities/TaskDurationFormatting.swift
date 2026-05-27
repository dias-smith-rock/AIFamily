import Foundation

/// 任务时长（分钟）→ 可读文案。
enum TaskDurationFormatting {
    static func readableDuration(minutes: Int, locale: Locale) -> String {
        let total = max(0, minutes)
        if total == 0 {
            return AppLocalized.string("0 min", locale: locale)
        }

        let hours = total / 60
        let remainder = total % 60

        if hours == 0 {
            return String(format: AppLocalized.string("%lld min", locale: locale), remainder)
        }
        if remainder == 0 {
            return String(format: AppLocalized.string("%lld hr", locale: locale), hours)
        }
        return String(
            format: AppLocalized.string("%lld hr %lld min", locale: locale),
            hours,
            remainder
        )
    }
}
