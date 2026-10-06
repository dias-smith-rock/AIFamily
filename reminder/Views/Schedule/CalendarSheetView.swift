import SwiftUI

/// 从顶栏选择的「按月」日历浮层。
struct CalendarSheetView: View {
    @Binding var selectedDate: Date
    let monthTaskDots: [Date: [Color]]
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var monthOffset: Int
    @State private var headerMonth: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let weekRowCount = 6
    private let dayCellMinHeight: CGFloat = 44
    private let gridSpacing: CGFloat = 8

    init(selectedDate: Binding<Date>, monthTaskDots: [Date: [Color]]) {
        self._selectedDate = selectedDate
        self.monthTaskDots = monthTaskDots
        let calendar = Self.displayCalendar()
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: selectedDate.wrappedValue)
        ) ?? selectedDate.wrappedValue
        self._headerMonth = State(initialValue: monthStart)
        self._monthOffset = State(initialValue: Self.clampedMonthOffset(from: selectedDate.wrappedValue, calendar: calendar))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(headerText)
                    .font(.title2.bold())
                Spacer()
                Button(L10n.Common.today) {
                    selectedDate = dayID(Date())
                    withAnimation(.easeInOut(duration: 0.25)) {
                        monthOffset = 0
                        headerMonth = monthDate(for: 0)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Circle())
                }
            }

            HStack {
                ForEach(Array(localizedShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            TabView(selection: $monthOffset) {
                ForEach(-12...12, id: \.self) { offset in
                    monthGrid(for: offset)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: monthGridHeight)
            .clipped()
            .onChange(of: monthOffset) { _, newOffset in
                headerMonth = monthDate(for: newOffset)
            }
            .onChange(of: selectedDate) { _, newDate in
                let visibleOffset = Self.clampedMonthOffset(from: newDate, calendar: calendar)
                if visibleOffset != monthOffset {
                    monthOffset = visibleOffset
                    headerMonth = monthDate(for: visibleOffset)
                }
            }
        }
        .padding(16)
    }

    private var monthGridHeight: CGFloat {
        CGFloat(weekRowCount) * dayCellMinHeight + CGFloat(weekRowCount - 1) * gridSpacing
    }

    private var calendar: Calendar {
        Self.displayCalendar(locale: locale)
    }

    @ViewBuilder
    private func monthGrid(for offset: Int) -> some View {
        let month = monthDate(for: offset)
        let cells = monthGridCells(for: month)
        LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(cells.indices, id: \.self) { index in
                if let date = cells[index] {
                    Button {
                        selectedDate = dayID(date)
                    } label: {
                        VStack(spacing: 4) {
                            Text(String(calendar.component(.day, from: date)))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isSelected(date) ? .white : .primary)

                            HStack(spacing: 3) {
                                let dots = monthTaskDots[calendar.startOfDay(for: date)] ?? []
                                ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, color in
                                    Circle()
                                        .fill(isSelected(date) ? Color.white : color)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(height: 8)
                        }
                        .frame(maxWidth: .infinity, minHeight: dayCellMinHeight)
                        .background(isSelected(date) ? Color.black : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(height: dayCellMinHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var headerText: String {
        headerMonth.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    private var localizedShortWeekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        guard first > 0, first < symbols.count else { return symbols }
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private func monthGridCells(for monthBaseDate: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthBaseDate) else {
            return Array(repeating: nil, count: weekRowCount * 7)
        }

        let firstDay = monthInterval.start
        let totalDays = calendar.dateComponents([.day], from: firstDay, to: monthInterval.end).day ?? 0
        let weekdayOfFirstDay = calendar.component(.weekday, from: firstDay)
        let leadingSlots = (weekdayOfFirstDay - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingSlots)
        for dayOffset in 0..<totalDays {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) {
                cells.append(date)
            }
        }
        while cells.count < weekRowCount * 7 {
            cells.append(nil)
        }
        if cells.count > weekRowCount * 7 {
            cells = Array(cells.prefix(weekRowCount * 7))
        }
        return cells
    }

    private func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func monthDate(for offset: Int) -> Date {
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return calendar.date(byAdding: .month, value: offset, to: currentMonthStart) ?? currentMonthStart
    }

    private func dayID(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func displayCalendar(locale: Locale? = nil) -> Calendar {
        var calendar = AppDisplayTimeZone.calendar()
        if let locale {
            calendar.locale = locale
        }
        return calendar
    }

    private static func clampedMonthOffset(from date: Date, calendar: Calendar) -> Int {
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let targetMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let diff = calendar.dateComponents([.month], from: currentMonthStart, to: targetMonthStart).month ?? 0
        return max(-12, min(12, diff))
    }
}
