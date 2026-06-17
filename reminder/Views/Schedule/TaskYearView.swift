import SwiftUI

/// 年视图：全年忙碌度热力看板 + 日期导航中枢。
struct TaskYearView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: ScheduleViewModel

    @Binding var selectedDate: Date
    let onMonthSelected: (Date) -> Void
    let onDateSelected: (Date) -> Void

    @State private var hapticToken = 0

    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            yearHeader

            if let snapshot = viewModel.yearCalendarSnapshot {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: monthColumns, spacing: 10) {
                        ForEach(snapshot.months) { month in
                            MicroMonthView(
                                month: month,
                                weekdaySymbols: snapshot.weekdaySymbols,
                                taskDensityByDayKey: snapshot.taskDensityByDayKey,
                                selectedDayKey: selectedDayKey,
                                onMonthSelected: {
                                    triggerHaptic()
                                    onMonthSelected(month.monthStart)
                                },
                                onDateSelected: { date in
                                    triggerHaptic()
                                    onDateSelected(date)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.background.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: hapticToken)
        .onAppear {
            viewModel.refreshYearViewSnapshot(locale: locale)
        }
        .onChange(of: viewModel.scheduledTasks) { _, _ in
            viewModel.refreshYearViewSnapshot(locale: locale)
        }
        .onChange(of: locale) { _, _ in
            viewModel.refreshYearViewSnapshot(locale: locale)
        }
    }

    private var yearHeader: some View {
        HStack {
            Button {
                shiftYear(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Schedule.previousYear.localized)

            Spacer(minLength: 0)

            Text(verbatim: "\(viewModel.yearViewSelectedYear)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Spacer(minLength: 0)

            Button {
                shiftYear(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Schedule.nextYear.localized)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var selectedDayKey: String? {
        YearCalendarBuilder.dayKey(for: selectedDate)
    }

    private func shiftYear(by delta: Int) {
        triggerHaptic()
        viewModel.setYearViewYear(viewModel.yearViewSelectedYear + delta, locale: locale)
    }

    private func triggerHaptic() {
        hapticToken += 1
    }
}
