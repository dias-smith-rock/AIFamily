import SwiftUI

/// 从顶栏选择的「按月」日历浮层。
struct CalendarSheetView: View {
    @Binding var selectedDate: Date
    let monthTaskDots: [Date: [Color]]
    @Environment(\.dismiss) private var dismiss
    @State private var monthOffset = 0
    @State private var headerMonth: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    init(selectedDate: Binding<Date>, monthTaskDots: [Date: [Color]]) {
        self._selectedDate = selectedDate
        self.monthTaskDots = monthTaskDots
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedDate.wrappedValue)) ?? selectedDate.wrappedValue
        self._headerMonth = State(initialValue: monthStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(headerText)
                    .font(.title2.bold())
                Spacer()
                Button("Today") {
                    selectedDate = dayID(Date())
                    withAnimation(.easeInOut(duration: 0.25)) {
                        monthOffset = 0
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
                ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            TabView(selection: $monthOffset) {
                ForEach(-12...12, id: \.self) { offset in
                    let month = monthDate(for: offset)
                    let cells = monthGridCells(for: month)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(cells.indices, id: \.self) { index in
                            if let date = cells[index] {
                                Button {
                                    selectedDate = dayID(date)
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(date.formatted(.dateTime.day()))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(isSelected(date) ? .white : .primary)

                                        HStack(spacing: 3) {
                                            let dots = monthTaskDots[Calendar.current.startOfDay(for: date)] ?? []
                                            ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, color in
                                                Circle()
                                                    .fill(isSelected(date) ? Color.white : color)
                                                    .frame(width: 5, height: 5)
                                            }
                                        }
                                        .frame(height: 8)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(isSelected(date) ? Color.black : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear
                                    .frame(height: 44)
                            }
                        }
                    }
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: monthOffset) { _, newOffset in
                headerMonth = monthDate(for: newOffset)
            }
            .onChange(of: selectedDate) { _, newDate in
                let visibleOffset = monthOffsetDateDifference(from: newDate)
                if (-12...12).contains(visibleOffset), visibleOffset != monthOffset {
                    monthOffset = visibleOffset
                    headerMonth = monthDate(for: visibleOffset)
                }
            }
        }
        .padding(16)
    }

    private var headerText: String {
        headerMonth.formatted(.dateTime.month(.wide).year())
    }

    private func monthGridCells(for monthBaseDate: Date) -> [Date?] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: monthBaseDate)
        else {
            return []
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
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return cells
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func monthDate(for offset: Int) -> Date {
        let calendar = Calendar.current
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return calendar.date(byAdding: .month, value: offset, to: currentMonthStart) ?? currentMonthStart
    }

    private func monthOffsetDateDifference(from date: Date) -> Int {
        let calendar = Calendar.current
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let targetMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let diff = calendar.dateComponents([.month], from: currentMonthStart, to: targetMonthStart).month ?? 0
        return max(-12, min(12, diff))
    }

    private func dayID(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
