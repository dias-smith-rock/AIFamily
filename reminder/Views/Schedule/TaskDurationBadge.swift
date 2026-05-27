import SwiftUI

/// 任务时长胶囊标签（卡片 / 详情复用）。
struct TaskDurationBadge: View {
    @Environment(\.locale) private var locale
    let minutes: Int

    var body: some View {
        Text(TaskDurationFormatting.readableDuration(minutes: minutes, locale: locale))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.gray.opacity(0.1))
            .clipShape(Capsule())
    }
}
