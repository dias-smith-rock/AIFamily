import SwiftUI

/// 日视图 / 周视图共用的顶部周条外框。
struct ScheduleWeekDayStripChrome<Content: View>: View {
    @ViewBuilder var strip: () -> Content

    var body: some View {
        strip()
            .frame(maxWidth: .infinity)
            .frame(height: 84, alignment: .top)
            .padding(.horizontal, 16)
    }
}

/// 周条中单日单元格（与日视图一致：字号、间距、选中/今日、任务点）。
struct ScheduleWeekDayStripCell: View {
    let date: Date
    let isSelected: Bool
    let taskCount: Int
    let locale: Locale
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? AppTheme.ColorToken.accent : .secondary)

                Text(String(AppDisplayTimeZone.calendar().component(.day, from: date)))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 36, maxHeight: 36)
                    .background {
                        if isSelected {
                            Circle()
                                .fill(AppTheme.ColorToken.accent)
                        } else if AppDisplayTimeZone.calendar().isDateInToday(date) {
                            Circle()
                                .stroke(AppTheme.ColorToken.accent, lineWidth: 2)
                        }
                    }

                HStack(spacing: 3) {
                    if taskCount >= 1 {
                        Circle()
                            .fill(.blue)
                            .frame(width: 4, height: 4)
                    }
                    if taskCount >= 3 {
                        Circle()
                            .fill(.orange)
                            .frame(width: 4, height: 4)
                    }
                    if taskCount >= 5 {
                        Circle()
                            .fill(.red)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
