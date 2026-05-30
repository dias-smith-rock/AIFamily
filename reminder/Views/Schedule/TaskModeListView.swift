import SwiftUI

/// 列表模式：按自然日分组的专业日历式纵向列表。
struct TaskModeListView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: ScheduleViewModel
    var listScrollToken: Int = 0
    var onTaskTap: ((FamilyTask) -> Void)?
    var onRefresh: (() async -> Void)?

    /// 按日历日分组（忽略时分），日期升序；组内按锚点时间升序。
    private var groupedTasks: [(Date, [FamilyTask])] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: viewModel.scheduledTasks) { cal.startOfDay(for: anchorDate(for: $0)) }
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
            if viewModel.isLoading {
                pullToRefreshScrollContainer(minHeight: 360) {
                    ProgressView(AppLocalized.string("正在加载任务...", locale: locale))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
            } else if let message = viewModel.errorMessage {
                pullToRefreshScrollContainer(minHeight: 360) {
                    ContentUnavailableView {
                        Label(AppLocalized.string("加载失败", locale: locale), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    }
                }
            } else if viewModel.scheduledTasks.isEmpty {
                pullToRefreshScrollContainer(minHeight: 360) {
                    ContentUnavailableView {
                        Label(AppLocalized.string("暂无任务", locale: locale), systemImage: "checklist")
                    } description: {
                        Text(AppLocalized.string("创建任务后将显示在此列表。", locale: locale))
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(daySections) { section in
                                VStack(alignment: .leading, spacing: 12) {
                                    dateHeader(for: section.id)

                                    ForEach(section.tasks) { task in
                                        TaskModeListMinimalRow(
                                            task: task,
                                            displayTitle: viewModel.displayTitle(for: task),
                                            forWhomAvatars: viewModel.forWhomAvatarSources(for: task)
                                        )
                                        .id(task.id)
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
                    .refreshable {
                        await onRefresh?()
                    }
                    .onChange(of: listScrollToken) { _, _ in
                        scrollToTargetTask(using: proxy)
                    }
                    .onAppear {
                        scrollToTargetTask(using: proxy)
                    }
                }
            }
        }
    }

    private func pullToRefreshScrollContainer<Content: View>(
        minHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .refreshable {
            await onRefresh?()
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
        .onAppear {
            viewModel.noteVisibleMonth(containing: day)
        }
    }

    // MARK: - Helpers

    private func anchorDate(for task: FamilyTask) -> Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private func scrollToTargetTask(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard let targetId = viewModel.getTargetTaskId() else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(targetId, anchor: .top)
            }
        }
    }
}

// MARK: - Section model

private struct TaskModeListDaySection: Identifiable {
    let id: Date
    let tasks: [FamilyTask]
}

// MARK: - Minimal row

private struct TaskModeListMinimalRow: View {
    @Environment(\.locale) private var locale

    let task: FamilyTask
    let displayTitle: String
    let forWhomAvatars: [TaskCardAvatarSource]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color.taskCardLeadingAccent(fromHex: task.backgroundColor))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(timeRangeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let trail = locationTrail {
                    Text(trail)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            TaskCardForWhomTrailing(sources: forWhomAvatars, style: .compact)
                .padding(.trailing, 2)
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
            return AppLocalized.string("全天", locale: locale)
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
    TaskModeListView(viewModel: AppViewModels.makeScheduleViewModel())
}
