import SwiftUI

enum ScheduleTimelineMetrics {
    static let timeColumnWidth: CGFloat = 45
    static let rowSpacing: CGFloat = 8
    static let axisColumnWidth: CGFloat = 16
    static let dotSize: CGFloat = 12
    static let dotStrokeWidth: CGFloat = 2
    static let lineWidth: CGFloat = 2
    static let dotTopPadding: CGFloat = 4
    static let nowLineHeight: CGFloat = 1
    static let nowCapsuleEstimatedHalfHeight: CGFloat = 10
    static let defaultTaskDuration: TimeInterval = 3600
    /// 与 `ScheduleTaskAnchorFlow.compactGapHeight` / 任务间 `ScheduleAnchorGapSegment` 高度一致。
    static let taskFlowGapHeight: CGFloat = 40

    static var axisLineLeadingInset: CGFloat {
        timeColumnWidth + rowSpacing + (axisColumnWidth - lineWidth) / 2
    }
}

/// 时间轴「此刻」红底胶囊时间标签。
struct ScheduleNowTimeCapsule: View {
    let timeText: String

    var body: some View {
        Text(timeText)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.red))
    }
}

/// 日程时间轴单行：左时间列 + 中轴线列 + 右任务卡片。
struct TaskRowView: View {
    let task: FamilyTask
    let anchor: Date
    let forWhomAvatars: [TaskCardAvatarSource]
    let assigneeLabel: String
    let isCurrentActiveTask: Bool
    let startTime: Date
    let endTime: Date
    let nextStartTime: Date?
    let followingGapHeight: CGFloat
    let now: Date
    let onTap: () -> Void

    @State private var rowHeight: CGFloat = 0

    private var timeText: String {
        anchor.formatted(date: .omitted, time: .shortened)
    }

    /// 红线 Y 轴锚点：任务内在卡片高度内滑动；空档期在卡片下方缝隙中继续向下一任务推进。
    private func calculateRedLineYOffset(cardHeight: CGFloat) -> CGFloat {
        guard isCurrentActiveTask else { return 0 }

        if now < startTime { return 0 }

        if now >= startTime, now < endTime {
            let totalDuration = endTime.timeIntervalSince(startTime)
            guard totalDuration > 0 else { return cardHeight }
            let elapsed = now.timeIntervalSince(startTime)
            let ratio = max(0, min(1, elapsed / totalDuration))
            return cardHeight * CGFloat(ratio)
        }

        let gapHeight = max(0, followingGapHeight)
        let resolvedNextStart = nextStartTime
            ?? Calendar.current.date(byAdding: .hour, value: 2, to: endTime)
            ?? endTime

        if now >= endTime, now < resolvedNextStart, gapHeight > 0 {
            let gapDuration = resolvedNextStart.timeIntervalSince(endTime)
            let elapsedGap = now.timeIntervalSince(endTime)
            let gapRatio = gapDuration > 0 ? max(0, min(1, elapsedGap / gapDuration)) : 1
            return cardHeight + gapHeight * CGFloat(gapRatio)
        }

        if now >= endTime {
            return cardHeight + gapHeight
        }

        return 0
    }

    private var nowIndicatorContainerHeight: CGFloat {
        rowHeight + max(0, followingGapHeight)
    }

    var body: some View {
        HStack(alignment: .top, spacing: ScheduleTimelineMetrics.rowSpacing) {
            timeColumn
            axisDotColumn
            cardColumn
        }
        .overlay(alignment: .topLeading) {
            if isCurrentActiveTask, followingGapHeight > 0, rowHeight > 0 {
                gapAxisConnectorLine
            }
        }
        .overlay(alignment: .topLeading) {
            if isCurrentActiveTask, rowHeight > 0 {
                TaskRowNowIndicatorOverlay(
                    now: now,
                    anchorY: calculateRedLineYOffset(cardHeight: rowHeight),
                    containerHeight: nowIndicatorContainerHeight
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .zIndex(1)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            if abs(height - rowHeight) > 0.5 {
                rowHeight = height
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var gapAxisConnectorLine: some View {
        let lineLeading = ScheduleTimelineMetrics.timeColumnWidth
            + ScheduleTimelineMetrics.rowSpacing
            + (ScheduleTimelineMetrics.axisColumnWidth - ScheduleTimelineMetrics.lineWidth) / 2
        let lineTop = ScheduleTimelineMetrics.dotTopPadding + ScheduleTimelineMetrics.dotSize / 2
        let lineHeight = max(0, nowIndicatorContainerHeight - lineTop)

        return Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: ScheduleTimelineMetrics.lineWidth, height: lineHeight)
            .offset(x: lineLeading, y: lineTop)
            .allowsHitTesting(false)
    }

    // MARK: - 左：时间

    private var timeColumn: some View {
        Text(timeText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            .frame(width: ScheduleTimelineMetrics.timeColumnWidth, alignment: .trailing)
    }

    // MARK: - 中：状态圆点

    private var axisDotColumn: some View {
        timelineDot(fill: statusDotColor)
            .frame(width: ScheduleTimelineMetrics.axisColumnWidth)
    }

    private func timelineDot(fill: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(
                width: ScheduleTimelineMetrics.dotSize,
                height: ScheduleTimelineMetrics.dotSize
            )
            .overlay {
                Circle()
                    .stroke(Color.white, lineWidth: ScheduleTimelineMetrics.dotStrokeWidth)
            }
            .padding(.top, ScheduleTimelineMetrics.dotTopPadding)
    }

    // MARK: - 右：卡片

    private var cardColumn: some View {
        TaskCardView(
            task: task,
            forWhomAvatars: forWhomAvatars,
            assigneeLabel: assigneeLabel
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var statusDotColor: Color {
        switch task.status {
        case .new:
            return .blue
        case .accepted, .inProgress:
            return .orange
        case .completed:
            return .green
        case .issue, .expired, .failed, .cancelled:
            return .red
        }
    }
}

// MARK: - 此刻指示器（overlay，不参与布局）

private struct TaskRowNowIndicatorOverlay: View {
    let now: Date
    let anchorY: CGFloat
    let containerHeight: CGFloat

    private var nowTimeText: String {
        now.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        let dotCenterOffset = anchorY - ScheduleTimelineMetrics.dotSize / 2
        let capsuleOffset = anchorY - ScheduleTimelineMetrics.nowCapsuleEstimatedHalfHeight
        let lineOffset = anchorY - ScheduleTimelineMetrics.nowLineHeight / 2

        HStack(alignment: .top, spacing: ScheduleTimelineMetrics.rowSpacing) {
            ScheduleNowTimeCapsule(timeText: nowTimeText)
                .frame(width: ScheduleTimelineMetrics.timeColumnWidth, alignment: .trailing)
                .offset(y: capsuleOffset)

            Circle()
                .fill(Color.red)
                .frame(
                    width: ScheduleTimelineMetrics.dotSize,
                    height: ScheduleTimelineMetrics.dotSize
                )
                .overlay {
                    Circle()
                        .stroke(Color.white, lineWidth: ScheduleTimelineMetrics.dotStrokeWidth)
                }
                .frame(width: ScheduleTimelineMetrics.axisColumnWidth)
                .offset(y: dotCenterOffset)

            Rectangle()
                .fill(Color.red)
                .frame(height: ScheduleTimelineMetrics.nowLineHeight)
                .frame(maxWidth: .infinity)
                .offset(y: lineOffset)
        }
        .frame(height: containerHeight, alignment: .topLeading)
    }
}
