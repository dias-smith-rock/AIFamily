import SwiftUI

/// 列表模式：按自然日分组的专业日历式纵向列表。
struct TaskModeListView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: ScheduleViewModel
    var listScrollToken: Int = 0
    /// 切换到列表时定位的目标日（通常为今天 / 当前选中日）。
    var scrollAnchorDate: Date = Date()
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
                    ProgressView(AppLocalized.string(L10n.Schedule.loadingTasks, locale: locale))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
            } else if let message = viewModel.errorMessage {
                pullToRefreshScrollContainer(minHeight: 360) {
                    ContentUnavailableView {
                        Label(AppLocalized.string(L10n.Common.loading, locale: locale), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    }
                }
            } else if viewModel.scheduledTasks.isEmpty {
                pullToRefreshScrollContainer(minHeight: 360) {
                    ContentUnavailableView {
                        Label(AppLocalized.string(L10n.Schedule.noTasksYet, locale: locale), systemImage: "checklist")
                    } description: {
                        Text(AppLocalized.string(L10n.Schedule.afterTheTaskIsCreatedItWillAppearInThis, locale: locale))
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
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            onTaskTap?(task)
                                        }
                                    }
                                }
                                .id(section.id)
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
                        scrollToCurrentDate(using: proxy)
                    }
                    .onAppear {
                        scrollToCurrentDate(using: proxy)
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

    /// 定位到目标日分组；无当天任务则落到之后最近一天，再否则最后一天。
    private func scrollToCurrentDate(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard let destination = scrollDestinationDay() else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(destination, anchor: .top)
            }
        }
    }

    private func scrollDestinationDay() -> Date? {
        let cal = Calendar.current
        let target = cal.startOfDay(for: scrollAnchorDate)
        if let exact = daySections.first(where: { cal.isDate($0.id, inSameDayAs: target) }) {
            return exact.id
        }
        if let future = daySections.first(where: { $0.id > target }) {
            return future.id
        }
        return daySections.last?.id
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

    private var orgColor: Color {
        HouseholdColorStore.color(for: task.householdId)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cardTitleText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(timeRangeLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))

                if let trail = locationTrail {
                    Text(trail)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            TaskCardAssigneeTrailing(forWhomAvatars: forWhomAvatars, style: .compact)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(orgColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var cardTitleText: String {
        guard task.status == .completed else { return displayTitle }
        return "✅ \(displayTitle)"
    }

    private var timeRangeLabel: String {
        if task.isAllDay {
            return AppLocalized.string(L10n.Common.allDay, locale: locale)
        }
        return ScheduleTimeFormatting.timelineClockRange(
            start: task.scheduleStartDate,
            end: task.timelineEndDate,
            locale: locale
        )
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
