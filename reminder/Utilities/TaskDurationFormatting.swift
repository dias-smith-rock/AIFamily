import Foundation

/// 任务时长（分钟）→ 可读文案。
enum TaskDurationFormatting {
    static func readableDuration(minutes: Int, locale: Locale) -> String {
        let total = max(0, minutes)
        if total == 0 {
            return AppLocalized.string(L10n.Common.n0Min, locale: locale)
        }

        let hours = total / 60
        let remainder = total % 60

        if hours == 0 {
            return String(format: AppLocalized.string(L10n.Common.lldMin, locale: locale), remainder)
        }
        if remainder == 0 {
            return String(format: AppLocalized.string(L10n.Common.lldHr, locale: locale), hours)
        }
        return String(
            format: AppLocalized.string(L10n.Common.lldHrLldMin, locale: locale),
            hours,
            remainder
        )
    }
}
