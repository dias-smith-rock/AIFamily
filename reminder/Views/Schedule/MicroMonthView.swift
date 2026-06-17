import SwiftUI

/// 年视图微缩月份：月份标题 + 7 列日期热力矩阵。
struct MicroMonthView: View {
    let month: YearMonthGridData
    let weekdaySymbols: [String]
    let taskDensityByDayKey: [String: Int]
    let selectedDayKey: String?
    let onMonthSelected: () -> Void
    let onDateSelected: (Date) -> Void

    private let dayColumns = Array(repeating: GridItem(.flexible(minimum: 8), spacing: 0), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onMonthSelected) {
                Text(month.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: dayColumns, spacing: 1) {
                ForEach(month.cells) { cell in
                    MicroMonthDayCell(
                        cell: cell,
                        taskCount: cell.isInMonth ? (taskDensityByDayKey[cell.dayKey] ?? 0) : 0,
                        isSelected: cell.dayKey == selectedDayKey,
                        onTap: {
                            guard let date = cell.date else { return }
                            onDateSelected(date)
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(AppTheme.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.ColorToken.border, lineWidth: 0.5)
        }
    }
}

private struct MicroMonthDayCell: View {
    let cell: YearDayCellData
    let taskCount: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if cell.isInMonth, taskCount > 0 {
                    Circle()
                        .fill(
                            AppTheme.ColorToken.accent.opacity(
                                YearHeatmapMetrics.fillOpacity(taskCount: taskCount)
                            )
                        )
                        .frame(width: 16, height: 16)
                }

                if cell.isInMonth {
                    Text("\(cell.dayNumber)")
                        .font(.system(size: 8, weight: cell.isToday ? .bold : .regular))
                        .foregroundStyle(textColor)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(AppTheme.ColorToken.accent, lineWidth: 1)
                } else if cell.isToday {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(AppTheme.ColorToken.accent.opacity(0.55), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(cell.isInMonth == false)
        .accessibilityHidden(cell.isInMonth == false)
    }

    private var textColor: Color {
        if cell.isToday {
            return AppTheme.ColorToken.accent
        }
        return .primary
    }
}
