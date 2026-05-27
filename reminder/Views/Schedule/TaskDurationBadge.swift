import SwiftUI

/// 任务时长胶囊标签（卡片 / 详情复用）。
struct TaskDurationBadge: View {
    let minutes: Int

    var body: some View {
        Text(minutes.taskDurationLocalizedKey)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.gray.opacity(0.1))
            .clipShape(Capsule())
    }
}
