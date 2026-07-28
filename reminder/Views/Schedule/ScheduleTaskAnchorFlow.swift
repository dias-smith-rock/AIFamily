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
    let displayTitle: (FamilyTask) -> String

    let onTaskTap: (FamilyTask) -> Void
    @State private var taskRowFrames: [UUID: CGRect] = [:]

    private var sortedTasks: [FamilyTask] {
        ScheduleTimelineMetrics.sortedForTimeline(timedTasks, anchor: taskAnchor)
    }

    private var viewingToday: Bool {
        AppDisplayTimeZone.calendar().isDateInToday(selectedCalendarDay)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(Array(sortedTasks.enumerated()), id: \.element.id) { index, task in
                        let startTime = taskAnchor(task)
                        let showTimeIndicator = index == 0
                            || ScheduleTimelineMetrics.anchorsShareTimelineLabel(
                                startTime,
                                taskAnchor(sortedTasks[index - 1])
                            ) == false

                        if index > 0 {
                            let previous = sortedTasks[index - 1]
                            let previousAnchor = taskAnchor(previous)

                            if ScheduleTimelineMetrics.anchorsShareTimelineLabel(previousAnchor, startTime) == false {
                                ScheduleAnchorGapSegment(
                                    stableID: "gap-\(previous.id.uuidString)-\(task.id.uuidString)",
                                    previousAnchor: previousAnchor,
                                    nextAnchor: startTime,
                                    compactHeight: compactGapHeight,
                                    longIdleThreshold: longIdleThreshold
                                )
                            }
                        }

                        TaskRowView(
                            task: task,
                            displayTitle: displayTitle(task),
                            anchor: startTime,
                            showTimeIndicator: showTimeIndicator,
                            forWhomAvatars: forWhomAvatars(task),
                            assigneeLabel: assigneeLabel(task),
                            onTap: { onTaskTap(task) }
                        )
                        .background {
                            // 仅「今天」需要此刻指示器几何；其它日收集 Preference 会在换日动画中连帧写 State，易卡顿。
                            if viewingToday {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ScheduleTaskRowFramePreferenceKey.self,
                                        value: [task.id: proxy.frame(in: .named(ScheduleTaskAnchorFlowCoordinateSpace.id))]
                                    )
                                }
                            }
                        }
                        .id("task-\(task.id.uuidString)")
                    }
                }
                .onPreferenceChange(ScheduleTaskRowFramePreferenceKey.self) { newFrames in
                    guard viewingToday else {
                        if taskRowFrames.isEmpty == false {
                            taskRowFrames = [:]
                        }
                        return
                    }
                    guard framesMeaningfullyChanged(from: taskRowFrames, to: newFrames) else { return }
                    taskRowFrames = newFrames
                }

                if viewingToday,
                   let nowY = nowIndicatorOffsetY(for: now),
                   let contentHeight = timelineContentHeight {
                    TaskRowNowIndicatorOverlay(
                        now: now,
                        anchorY: nowY,
                        containerHeight: contentHeight
                    )
                    .id(ScheduleAnchorFlowScrollIDs.nowMarker)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .zIndex(1)
                }
            }
            .coordinateSpace(name: ScheduleTaskAnchorFlowCoordinateSpace.id)
            .padding(.vertical, 30)
        }
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

    private var timelineContentHeight: CGFloat? {
        let maxY = taskRowFrames.values.map(\.maxY).max()
        return maxY.map { $0 + 12 }
    }

    private func nowIndicatorOffsetY(for now: Date) -> CGFloat? {
        guard let firstTask = sortedTasks.first,
              let firstFrame = taskRowFrames[firstTask.id] else {
            return nil
        }

        if now < taskAnchor(firstTask) {
            return firstFrame.minY
        }

        for (index, task) in sortedTasks.enumerated() {
            guard let rowFrame = taskRowFrames[task.id] else { continue }
            let start = taskAnchor(task)
            let end = taskEnd(task)
            let nextStart = nextIntervalEnd(for: task, at: index)
            let effectiveEnd = end > start ? end : start.addingTimeInterval(1)

            if now >= start, now < effectiveEnd {
                let duration = effectiveEnd.timeIntervalSince(start)
                let progress = max(0, min(1, now.timeIntervalSince(start) / duration))
                return rowFrame.minY + rowFrame.height * progress
            }

            if now >= effectiveEnd, now < nextStart {
                let gapDuration = max(nextStart.timeIntervalSince(effectiveEnd), 1)
                let gapProgress = max(0, min(1, now.timeIntervalSince(effectiveEnd) / gapDuration))
                return rowFrame.maxY + compactGapHeight * gapProgress
            }
        }

        if let lastTask = sortedTasks.last,
           let lastFrame = taskRowFrames[lastTask.id] {
            return lastFrame.maxY
        }
        return nil
    }

    private func framesMeaningfullyChanged(
        from old: [UUID: CGRect],
        to new: [UUID: CGRect]
    ) -> Bool {
        guard old.count == new.count else { return true }
        for (id, rect) in new {
            guard let previous = old[id] else { return true }
            if abs(previous.minX - rect.minX) > 0.5
                || abs(previous.minY - rect.minY) > 0.5
                || abs(previous.width - rect.width) > 0.5
                || abs(previous.height - rect.height) > 0.5 {
                return true
            }
        }
        return false
    }
}

private enum ScheduleTaskAnchorFlowCoordinateSpace {
    static let id = "scheduleTaskAnchorFlow"
}

private struct ScheduleTaskRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
