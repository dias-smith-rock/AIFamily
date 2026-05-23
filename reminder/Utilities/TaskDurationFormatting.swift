import Foundation

/// 任务时长（分钟）→ 中文可读文案。
enum TaskDurationFormatting {
    static func readableDuration(minutes: Int) -> String {
        let total = max(0, minutes)
        if total == 0 {
            return "0分钟"
        }

        let hours = total / 60
        let remainder = total % 60

        if hours == 0 {
            return "\(remainder)分钟"
        }
        if remainder == 0 {
            return "\(hours)小时"
        }
        return "\(hours)小时\(remainder)分"
    }
}
