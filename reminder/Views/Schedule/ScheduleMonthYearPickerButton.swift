import SwiftUI

/// 日程第二行月份切换按钮（日视图周条右侧 / 周·列表·月视图顶栏下方共用）。
struct ScheduleMonthYearPickerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(AppTheme.ColorToken.accent)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(title)
    }
}
