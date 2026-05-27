import SwiftUI

extension Int {
    /// 任务时长文案（`LocalizedStringKey`，键与 `Localizable.xcstrings` 中 `%lld hr` / `%lld hr %lld min` 等一致）。
    var taskDurationLocalizedKey: LocalizedStringKey {
        let total = Swift.max(0, self)
        let hours = total / 60
        let remainder = total % 60

        if total == 0 {
            return "0 min"
        }
        if hours == 0 {
            return "\(remainder) min"
        }
        if remainder == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(remainder) min"
    }
}

/// 任务时长展示（在 View 层插值，匹配 String Catalog 中的 `%lld min` / `%lld hr` 等键）。
struct TaskDurationText: View {
    let minutes: Int

    var body: some View {
        Text(minutes.taskDurationLocalizedKey)
    }
}
