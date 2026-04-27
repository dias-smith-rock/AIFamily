import SwiftUI

struct ScheduleView: View {
    @StateObject private var viewModel = AppViewModels.makeScheduleViewModel()
    @State private var period: SchedulePeriod = .day
    @State private var anchorDate = Date.mockISO("2026-04-27T00:00:00.000Z")
    @State private var monthSheetDate: Date?
    @State private var showsMonthSheet = false

    enum SchedulePeriod: String, CaseIterable, Identifiable {
        case day = "日"
        case week = "周"
        case month = "月"
        case year = "年"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    periodSelector
                    periodNavigator
                    rangeHint
                    Divider()
                    contentByPeriod
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 120)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadTasks()
        }
        .sheet(isPresented: $showsMonthSheet) {
            if let selectedDate = monthSheetDate {
                MonthDayTasksSheet(
                    date: selectedDate,
                    tasks: tasks(on: selectedDate),
                    assigneeName: assigneeName(for:)
                ) { task in
                    let nextStatus: Task.TaskStatus = task.status == .completed ? .pending : .completed
                    await viewModel.updateTaskStatus(taskId: task.id, to: nextStatus)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
                .presentationCornerRadius(30)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("日程表")
                .font(.system(size: 36, weight: .bold))
            Text(headerDateText)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var periodSelector: some View {
        HStack(spacing: 8) {
            ForEach(SchedulePeriod.allCases) { option in
                Button {
                    period = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(period == option ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(period == option ? Color(.systemBackground) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: period)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var periodNavigator: some View {
        HStack {
            Button {
                shiftAnchor(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(periodRangeTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                shiftAnchor(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var rangeHint: some View {
        Text(hintTitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var contentByPeriod: some View {
        switch period {
        case .day:
            taskList(tasks: filteredTasks)
        case .week:
            weekView
        case .month:
            monthView
        case .year:
            yearView
        }
    }

    private func taskList(tasks: [Task]) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(tasks) { task in
                ScheduleTaskCard(
                    task: task,
                    assigneeName: assigneeName(for: task.assigneeId),
                    onToggleStatus: {
                        let nextStatus: Task.TaskStatus = task.status == .completed ? .pending : .completed
                        await viewModel.updateTaskStatus(taskId: task.id, to: nextStatus)
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: tasks)
    }

    private var weekView: some View {
        let days = weekDates
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    let dayTasks = tasks(on: date)
                    VStack(spacing: 6) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.day()))
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Calendar.current.isDate(date, inSameDayAs: anchorDate) ? Color.blue.opacity(0.15) : .clear)
                            .clipShape(Circle())
                        Text("\(dayTasks.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(dayTasks.isEmpty ? Color.secondary : Color.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            anchorDate = date
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            taskList(tasks: filteredTasks)
        }
    }

    private var monthView: some View {
        let calendar = Calendar.current
        let cells = monthCells
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        return VStack(spacing: 10) {
            HStack {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells.indices, id: \.self) { index in
                    if let date = cells[index] {
                        MonthDateCell(
                            date: date,
                            tasks: tasks(on: date),
                            isSelected: calendar.isDate(date, inSameDayAs: anchorDate),
                            colorForMember: colorForMember
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                anchorDate = date
                            }
                            monthSheetDate = date
                            showsMonthSheet = true
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.clear)
                            .frame(height: 56)
                    }
                }
            }
            .padding(8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var yearView: some View {
        let months = (1...12).compactMap { month -> Date? in
            Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: anchorDate), month: month, day: 1))
        }

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(months, id: \.self) { monthStart in
                YearMonthHeatCell(
                    monthStart: monthStart,
                    taskCount: tasks(inMonthOf: monthStart).count,
                    intensity: monthIntensity(for: monthStart)
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        anchorDate = monthStart
                        period = .month
                    }
                }
            }
        }
    }

    private var filteredTasks: [Task] {
        viewModel.tasks.filter { task in
            switch period {
            case .day:
                return Calendar.current.isDate(task.scheduledAt, inSameDayAs: anchorDate)
            case .week:
                return Calendar.current.isDate(task.scheduledAt, equalTo: anchorDate, toGranularity: .weekOfYear)
            case .month:
                return Calendar.current.isDate(task.scheduledAt, equalTo: anchorDate, toGranularity: .month)
            case .year:
                return Calendar.current.isDate(task.scheduledAt, equalTo: anchorDate, toGranularity: .year)
            }
        }
    }

    private var weekDates: [Date] {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: anchorDate) else { return [] }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var monthCells: [Date?] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: anchorDate),
            let firstWeekday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: monthInterval.start))
        else { return [] }

        let numberOfDays = calendar.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? 0
        let offset = calendar.dateComponents([.day], from: firstWeekday, to: monthInterval.start).day ?? 0
        let leadingEmpty = max(0, offset)

        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in 0..<numberOfDays {
            let date = calendar.date(byAdding: .day, value: day, to: monthInterval.start)
            cells.append(date)
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var periodRangeTitle: String {
        let calendar = Calendar.current
        switch period {
        case .day:
            return anchorDate.formatted(.dateTime.year().month().day())
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDate) else { return "本周任务" }
            return "\(interval.start.formatted(.dateTime.month().day())) - \(interval.end.addingTimeInterval(-1).formatted(.dateTime.month().day()))"
        case .month:
            return anchorDate.formatted(.dateTime.year().month())
        case .year:
            return anchorDate.formatted(.dateTime.year())
        }
    }

    private var hintTitle: String {
        switch period {
        case .day:
            return "当日时间轴"
        case .week:
            return "7天任务密度预览"
        case .month:
            return "圆点颜色代表不同成员"
        case .year:
            return "热力深浅代表任务数量"
        }
    }

    private var headerDateText: String {
        switch period {
        case .day:
            return anchorDate.formatted(.dateTime.year().month().day().weekday(.wide))
        case .week:
            return "周视图"
        case .month:
            return "月视图"
        case .year:
            return "年视图"
        }
    }

    private func shiftAnchor(by value: Int) {
        let component: Calendar.Component
        switch period {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .year:
            component = .year
        }
        if let next = Calendar.current.date(byAdding: component, value: value, to: anchorDate) {
            withAnimation(.easeInOut(duration: 0.2)) {
                anchorDate = next
            }
        }
    }

    private func tasks(on date: Date) -> [Task] {
        viewModel.tasks.filter { Calendar.current.isDate($0.scheduledAt, inSameDayAs: date) }
    }

    private func tasks(inMonthOf date: Date) -> [Task] {
        viewModel.tasks.filter { Calendar.current.isDate($0.scheduledAt, equalTo: date, toGranularity: .month) }
    }

    private func monthIntensity(for monthStart: Date) -> Double {
        let count = Double(tasks(inMonthOf: monthStart).count)
        return min(1, count / 8.0)
    }

    private func assigneeName(for id: UUID) -> String {
        FamilyMember.mockMembers.first(where: { $0.id == id })?.displayName ?? "执行人"
    }

    private func colorForMember(_ memberId: UUID) -> Color {
        let palette: [Color] = [.green, .blue, .orange, .purple, .pink, .teal]
        let index = abs(memberId.hashValue) % palette.count
        return palette[index]
    }
}

private struct MonthDayTasksSheet: View {
    let date: Date
    let tasks: [Task]
    let assigneeName: (UUID) -> String
    let onToggleStatus: (Task) async -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if tasks.isEmpty {
                            ContentUnavailableView(
                                "当天暂无任务",
                                systemImage: "calendar.badge.exclamationmark",
                                description: Text("可以通过 AI 助手快速创建任务")
                            )
                            .padding(.top, 34)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(tasks) { task in
                                    ScheduleTaskCard(
                                        task: task,
                                        assigneeName: assigneeName(task.assigneeId),
                                        onToggleStatus: {
                                            await onToggleStatus(task)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(SheetTopRoundedShape(radius: 30))
            .overlay(
                SheetTopRoundedShape(radius: 30)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
        }
    }

    private var sheetHeader: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.65))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            VStack(spacing: 2) {
                Text("当日详情")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(date.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }
}

private struct SheetTopRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topLeft = min(radius, min(rect.width, rect.height) / 2)
        let topRight = topLeft

        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: topLeft))
        path.addQuadCurve(to: CGPoint(x: topLeft, y: 0), control: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width - topRight, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: topRight), control: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()

        return path
    }
}

private struct MonthDateCell: View {
    let date: Date
    let tasks: [Task]
    let isSelected: Bool
    let colorForMember: (UUID) -> Color

    var body: some View {
        VStack(spacing: 4) {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .blue : .primary)

            HStack(spacing: 3) {
                ForEach(Array(uniqueMemberIds.prefix(3)), id: \.self) { memberId in
                    Circle()
                        .fill(colorForMember(memberId))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(isSelected ? Color.blue.opacity(0.12) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var uniqueMemberIds: [UUID] {
        Array(Set(tasks.map(\.assigneeId)))
    }
}

private struct YearMonthHeatCell: View {
    let monthStart: Date
    let taskCount: Int
    let intensity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthStart.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(max(0.08, intensity * 0.8)))
                .frame(height: 42)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(taskCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ScheduleTaskCard: View {
    let task: Task
    let assigneeName: String
    let onToggleStatus: () async -> Void

    private var statusText: String {
        switch task.status {
        case .completed:
            return "已完成"
        case .pending:
            return "待执行"
        case .inProgress:
            return "执行中"
        case .overdue:
            return "已过期"
        }
    }

    private var cardColor: Color {
        switch task.status {
        case .completed:
            return .green.opacity(0.15)
        case .pending, .inProgress:
            return .blue.opacity(0.15)
        case .overdue:
            return .orange.opacity(0.2)
        }
    }

    private var borderColor: Color {
        switch task.status {
        case .completed:
            return .green.opacity(0.55)
        case .pending, .inProgress:
            return .blue.opacity(0.45)
        case .overdue:
            return .orange.opacity(0.55)
        }
    }

    private var statusIcon: String {
        switch task.status {
        case .completed:
            return "checkmark.circle"
        case .pending, .inProgress:
            return "clock"
        case .overdue:
            return "exclamationmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(statusText, systemImage: statusIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(assigneeName)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color(.systemBackground))
                    .clipShape(Capsule())
            }

            Label(task.scheduledAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text(task.title)
                .font(.system(size: 42, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                if let location = task.location {
                    Label(location, systemImage: "location")
                }
                if let childName = task.childName {
                    Label(childName, systemImage: "person")
                }
            }
            .font(.title3)
            .foregroundStyle(.secondary)

            Button {
                _Concurrency.Task {
                    await onToggleStatus()
                }
            } label: {
                Label(task.status == .completed ? "恢复待办" : "标记完成", systemImage: task.status == .completed ? "arrow.counterclockwise" : "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(task.status == .completed ? .orange : .green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground).opacity(0.85))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(borderColor, lineWidth: 2)
        )
        .contentTransition(.numericText())
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: task.status)
    }
}

#Preview {
    ScheduleView()
}
