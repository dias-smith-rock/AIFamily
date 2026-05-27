import SwiftUI

extension Int {
    /// 任务时长文案（`LocalizedStringKey`，键与 `Localizable.xcstrings` 中 `%lld分钟` / `%lld小时` 等一致）。
    var taskDurationLocalizedKey: LocalizedStringKey {
        let total = Swift.max(0, self)
        let hours = total / 60
        let remainder = total % 60

        if total == 0 {
            return "0分钟"
        }
        if hours == 0 {
            return "\(remainder)分钟"
        }
        if remainder == 0 {
            return "\(hours)小时"
        }
        return "\(hours)小时\(remainder)分钟"
    }
}

/// 任务时长展示（在 View 层插值，匹配 String Catalog 中的 `%lld分钟` / `%lld小时` 等键）。
struct TaskDurationText: View {
    let minutes: Int

    var body: some View {
        Text(minutes.taskDurationLocalizedKey)
    }
}
