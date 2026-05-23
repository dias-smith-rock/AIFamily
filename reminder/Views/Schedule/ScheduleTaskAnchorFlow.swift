import SwiftUI

/// 供 `ScrollViewReader.scrollTo` 定位「此刻」行。
enum ScheduleAnchorFlowScrollIDs {
    static let nowMarker = "scheduleAnchorFlowNow"
}

/// 定时任务锚点流：三列时间轴布局 + 任务间固定间隙；锚点时间差大时用虚线表示长空闲。
struct ScheduleTaskAnchorFlow: View {
    let timedTasks: [FamilyTask]
    let selectedCalendarDay: Date
    let compactGapHeight: CGFloat
    let longIdleThreshold: TimeInterval

    let taskAnchor: (FamilyTask) -> Date
    let taskEnd: (FamilyTask) -> Date
    let forWhomAvatars: (FamilyTask) -> [TaskCardAvatarSource]
    let assigneeLabel: (FamilyTask) -> String

    let onTaskTap: (FamilyTask) -> Void

    private var sortedTasks: [FamilyTask] {
        timedTasks.sorted { taskAnchor($0) < taskAnchor($1) }
    }

    private var viewingToday: Bool {
        Calendar.current.isDateInToday(selectedCalendarDay)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let activeTaskID = activeTaskID(for: now)

            VStack(spacing: 0) {
                ForEach(Array(sortedTasks.enumerated()), id: \.element.id) { index, task in
                    let isCurrentActiveTask = viewingToday && activeTaskID == task.id
                    let startTime = taskAnchor(task)
                    let endTime = taskEnd(task)
                    let nextStartTime = nextIntervalEnd(for: task, at: index)
                    let followingGapHeight = index + 1 < sortedTasks.count ? compactGapHeight : 0

                    if index > 0 {
                        let previous = sortedTasks[index - 1]
                        let previousIsActive = viewingToday && activeTaskID == previous.id

                        ScheduleAnchorGapSegment(
                            stableID: "gap-\(previous.id.uuidString)-\(task.id.uuidString)",
                            previousAnchor: taskAnchor(previous),
                            nextAnchor: taskAnchor(task),
                            compactHeight: previousIsActive ? 0 : compactGapHeight,
                            longIdleThreshold: longIdleThreshold
                        )
                    }

                    TaskRowView(
                        task: task,
                        anchor: startTime,
                        forWhomAvatars: forWhomAvatars(task),
                        assigneeLabel: assigneeLabel(task),
                        isCurrentActiveTask: isCurrentActiveTask,
                        startTime: startTime,
                        endTime: endTime,
                        nextStartTime: nextStartTime,
                        followingGapHeight: followingGapHeight,
                        now: now,
                        onTap: { onTaskTap(task) }
                    )
                    .padding(.bottom, isCurrentActiveTask ? followingGapHeight : 0)
                    .id(isCurrentActiveTask ? ScheduleAnchorFlowScrollIDs.nowMarker : "task-\(task.id.uuidString)")
                }
            }
        }
    }

    /// 红线仅渲染在 `now ∈ [start, nextStart)` 的唯一任务行上。
    private func activeTaskID(for now: Date) -> UUID? {
        guard viewingToday else { return nil }

        for (index, task) in sortedTasks.enumerated() {
            let start = taskAnchor(task)
            let nextStart = nextIntervalEnd(for: task, at: index)
            if now >= start, now < nextStart {
                return task.id
            }
        }
        return nil
    }

    /// 进度区间终点：下一任务开始时间；末项任务则用结束时间或默认 60 分钟。
    private func nextIntervalEnd(for task: FamilyTask, at index: Int) -> Date {
        if index + 1 < sortedTasks.count {
            return taskAnchor(sortedTasks[index + 1])
        }

        let start = taskAnchor(task)
        let end = taskEnd(task)
        if end > start {
            return end
        }
        return start.addingTimeInterval(ScheduleTimelineMetrics.defaultTaskDuration)
    }
}

private struct ScheduleAnchorGapSegment: View {
    let stableID: String
    let previousAnchor: Date
    let nextAnchor: Date
    let compactHeight: CGFloat
    let longIdleThreshold: TimeInterval

    private var anchorGapLong: Bool {
        nextAnchor.timeIntervalSince(previousAnchor) >= longIdleThreshold
    }

    var body: some View {
        HStack(alignment: .center, spacing: ScheduleTimelineMetrics.rowSpacing) {
            Color.clear
                .frame(width: ScheduleTimelineMetrics.timeColumnWidth)

            Group {
                if anchorGapLong {
                    ScheduleAnchorGapDashedLine(height: compactHeight)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: ScheduleTimelineMetrics.lineWidth, height: compactHeight)
                }
            }
            .frame(width: ScheduleTimelineMetrics.axisColumnWidth)

            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: compactHeight)
        }
        .id(stableID)
    }
}

private struct ScheduleAnchorGapDashedLine: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .stroke(
                Color.gray.opacity(0.3),
                style: StrokeStyle(lineWidth: ScheduleTimelineMetrics.lineWidth, dash: [4, 4])
            )
            .frame(width: ScheduleTimelineMetrics.lineWidth, height: height)
    }
}
