import SwiftUI

private enum ScheduleNowMarker: Equatable {
    case none
    case onTask(UUID)
    case between(previousTaskID: UUID, nextTaskID: UUID)
}

/// 供 `ScrollViewReader.scrollTo` 定位「此刻」行。
enum ScheduleAnchorFlowScrollIDs {
    static let nowMarker = "scheduleAnchorFlowNow"
}

/// 定时任务锚点流：左侧 ~50pt 时间 + 竖线；右侧 `TaskCardView`。任务间固定 ~40pt 间隙，锚点时间差大时用虚线表示长空闲。
struct ScheduleTaskAnchorFlow<Card: View>: View {
    let timedTasks: [FamilyTask]
    let selectedCalendarDay: Date
    let timeColumnWidth: CGFloat
    let compactGapHeight: CGFloat
    let longIdleThreshold: TimeInterval

    let taskAnchor: (FamilyTask) -> Date
    let taskEnd: (FamilyTask) -> Date

    let onTaskTap: (FamilyTask) -> Void
    @ViewBuilder let card: (FamilyTask) -> Card

    private var sortedTasks: [FamilyTask] {
        timedTasks.sorted { taskAnchor($0) < taskAnchor($1) }
    }

    private var viewingToday: Bool {
        Calendar.current.isDateInToday(selectedCalendarDay)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let marker = resolveNowMarker(now: now)

            VStack(spacing: 0) {
                ForEach(Array(sortedTasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 {
                        let previous = sortedTasks[index - 1]
                        let gapKind: GapKind = {
                            if case let .between(prevID, nextID) = marker,
                               prevID == previous.id,
                               nextID == task.id {
                                return .containsNowMarker
                            }
                            return .normal
                        }()

                        ScheduleAnchorGapSegment(
                            stableID: "gap-\(previous.id.uuidString)-\(task.id.uuidString)",
                            previousAnchor: taskAnchor(previous),
                            nextAnchor: taskAnchor(task),
                            prevEnd: taskEnd(previous),
                            nextStart: taskAnchor(task),
                            compactHeight: compactGapHeight,
                            longIdleThreshold: longIdleThreshold,
                            timeColumnWidth: timeColumnWidth,
                            viewingToday: viewingToday,
                            now: now,
                            gapKind: gapKind
                        )
                    }

                    let ribbon: Bool = {
                        if case let .onTask(id) = marker { return id == task.id }
                        return false
                    }()

                    ScheduleAnchorTaskRow(
                        taskID: task.id,
                        anchor: taskAnchor(task),
                        timeColumnWidth: timeColumnWidth,
                        now: now,
                        showNowRibbon: ribbon,
                        rowNowMarker: ribbon,
                        card: card(task),
                        onTap: { onTaskTap(task) }
                    )
                }
            }
        }
    }

    private func resolveNowMarker(now: Date) -> ScheduleNowMarker {
        guard viewingToday else { return .none }

        for task in sortedTasks {
            let a = taskAnchor(task)
            let e = taskEnd(task)
            if now >= a, now <= e {
                return .onTask(task.id)
            }
        }

        guard sortedTasks.count >= 2 else { return .none }
        for index in 1..<sortedTasks.count {
            let previous = sortedTasks[index - 1]
            let next = sortedTasks[index]
            let prevEnd = taskEnd(previous)
            let nextStart = taskAnchor(next)
            if now > prevEnd, now < nextStart {
                return .between(previousTaskID: previous.id, nextTaskID: next.id)
            }
        }
        return .none
    }
}

private enum GapKind {
    case normal
    case containsNowMarker
}

private struct ScheduleAnchorGapSegment: View {
    let stableID: String
    let previousAnchor: Date
    let nextAnchor: Date
    let prevEnd: Date
    let nextStart: Date
    let compactHeight: CGFloat
    let longIdleThreshold: TimeInterval
    let timeColumnWidth: CGFloat
    let viewingToday: Bool
    let now: Date
    let gapKind: GapKind

    private var anchorGapLong: Bool {
        nextAnchor.timeIntervalSince(previousAnchor) >= longIdleThreshold
    }

    private var nowInThisGap: Bool {
        viewingToday && now > prevEnd && now < nextStart
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .center) {
                ScheduleVerticalConnectorLine(height: compactHeight, dashed: anchorGapLong)
                    .frame(width: timeColumnWidth)

                if gapKind == .containsNowMarker, nowInThisGap {
                    VStack(spacing: 2) {
                        Text(now.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.red)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    }
                    .frame(width: timeColumnWidth)
                }
            }

            Color.clear
                .frame(height: compactHeight)
                .frame(maxWidth: .infinity)
        }
        .id(gapKind == .containsNowMarker ? ScheduleAnchorFlowScrollIDs.nowMarker : stableID)
    }
}

private struct ScheduleAnchorTaskRow<Card: View>: View {
    let taskID: UUID
    let anchor: Date
    let timeColumnWidth: CGFloat
    let now: Date
    let showNowRibbon: Bool
    let rowNowMarker: Bool
    let card: Card
    let onTap: () -> Void

    private var timeText: String {
        anchor.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                GeometryReader { geo in
                    let topInset: CGFloat = 16
                    Rectangle()
                        .fill(Color.secondary.opacity(0.28))
                        .frame(width: 1)
                        .frame(height: max(0, geo.size.height - topInset))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, topInset)
                }
                .frame(width: timeColumnWidth)

                Text(timeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: timeColumnWidth, alignment: .leading)
                    .padding(.top, 2)
            }
            .frame(width: timeColumnWidth, alignment: .topTrailing)

            card
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .top) {
                    if showNowRibbon {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(now.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.red)
                                Spacer(minLength: 0)
                            }
                            Capsule()
                                .fill(Color.red.opacity(0.92))
                                .frame(height: 3)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.bottom, 6)
                        .offset(y: -8)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .id(rowNowMarker ? ScheduleAnchorFlowScrollIDs.nowMarker : "task-\(taskID.uuidString)")
    }
}

private struct ScheduleVerticalConnectorLine: View {
    let height: CGFloat
    let dashed: Bool

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 1, height: height)
            .overlay {
                Rectangle()
                    .stroke(
                        Color.secondary.opacity(0.35),
                        style: StrokeStyle(
                            lineWidth: 1,
                            lineCap: .round,
                            dash: dashed ? [4, 4] : []
                        )
                    )
            }
    }
}
