import SwiftUI

/// 列表模式：按自然日分组的专业日历式纵向列表。
struct TaskModeListView: View {
    let tasks: [FamilyTask]
    var isLoading: Bool = false
    var errorMessage: String?
    var onTaskTap: ((FamilyTask) -> Void)?

    /// 按日历日分组（忽略时分），日期升序；组内按锚点时间升序。
    private var groupedTasks: [(Date, [FamilyTask])] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: tasks) { cal.startOfDay(for: anchorDate(for: $0)) }
        let sortedDays = buckets.keys.sorted()
        return sortedDays.map { day in
            let sorted = (buckets[day] ?? []).sorted { anchorDate(for: $0) < anchorDate(for: $1) }
            return (day, sorted)
        }
    }

    private var daySections: [TaskModeListDaySection] {
        groupedTasks.map { TaskModeListDaySection(id: $0.0, tasks: $0.1) }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在加载任务...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = errorMessage {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tasks.isEmpty {
                ContentUnavailableView {
                    Label("暂无任务", systemImage: "checklist")
                } description: {
                    Text("创建任务后将显示在此列表。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(daySections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                dateHeader(for: section.id)

                                ForEach(section.tasks) { task in
                                    TaskModeListMinimalRow(task: task)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            onTaskTap?(task)
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Header

    private func dateHeader(for day: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 36, weight: .bold, design: .default))
                .foregroundStyle(.primary)

            Text(day.formatted(.dateTime.weekday(.wide)))
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func anchorDate(for task: FamilyTask) -> Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }
}

// MARK: - Section model

private struct TaskModeListDaySection: Identifiable {
    let id: Date
    let tasks: [FamilyTask]
}

// MARK: - Minimal row

private struct TaskModeListMinimalRow: View {
    let task: FamilyTask

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color.taskCardLeadingAccent(fromHex: task.backgroundColor))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(timeRangeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trail = locationTrail {
                Text(trail)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    private var rowFill: Color {
        Color(.secondarySystemBackground)
    }

    private var timeRangeLabel: String {
        if task.isAllDay {
            return "全天"
        }
        let cal = Calendar.current
        let start = task.dueDate ?? task.originalDueDate ?? task.createdAt
        let end = task.endDatetime ?? cal.date(byAdding: .hour, value: 1, to: start) ?? start
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        if startDay != endDay {
            return "00:00 – 23:59"
        }
        let tf = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(start.formatted(tf)) – \(end.formatted(tf))"
    }

    private var locationTrail: String? {
        let name = task.locationData?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = task.locationData?.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, name.isEmpty == false { return name }
        if let address, address.isEmpty == false {
            return address.count > 24 ? String(address.prefix(21)) + "…" : address
        }
        return nil
    }
}

#Preview("List grouped") {
    TaskModeListView(
        tasks: [],
        onTaskTap: { _ in }
    )
}
