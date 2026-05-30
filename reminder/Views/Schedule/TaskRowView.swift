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
    /// 同时间组内卡片之间的额外垂直间距（与 `TaskRowView` 底部 padding 一致）。
    static let stackedRowBottomSpacing: CGFloat = 8

    static var axisLineLeadingInset: CGFloat {
        timeColumnWidth + rowSpacing + (axisColumnWidth - lineWidth) / 2
    }

    /// 时间轴左侧标签是否视为「同一时刻」（精确到分钟）。
    static func anchorsShareTimelineLabel(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(lhs, equalTo: rhs, toGranularity: .minute)
    }

    /// 计划时间优先；同一分钟锚点内按 `createdAt` 升序（先创建的在上）。
    static func timelineSortsBefore(
        _ lhs: FamilyTask,
        _ rhs: FamilyTask,
        anchor: (FamilyTask) -> Date
    ) -> Bool {
        let lhsAnchor = anchor(lhs)
        let rhsAnchor = anchor(rhs)
        if anchorsShareTimelineLabel(lhsAnchor, rhsAnchor) {
            return lhs.createdAt < rhs.createdAt
        }
        return lhsAnchor < rhsAnchor
    }

    static func sortedForTimeline(
        _ tasks: [FamilyTask],
        anchor: (FamilyTask) -> Date
    ) -> [FamilyTask] {
        tasks.sorted { timelineSortsBefore($0, $1, anchor: anchor) }
    }
}

/// 时间轴「此刻」红底胶囊时间标签（须置于 `ScheduleTimelineMetrics.timeColumnWidth` 固定列内右对齐）。
struct ScheduleNowTimeCapsule: View {
    let timeText: String

    var body: some View {
        Text(timeText)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.red))
            .padding(2)
            .background(Capsule().fill(Color(.systemGroupedBackground)))
            .compositingGroup()
            .frame(width: ScheduleTimelineMetrics.timeColumnWidth, alignment: .trailing)
    }
}

/// 日程时间轴单行：左时间列 + 中轴线列 + 右任务卡片。
struct TaskRowView: View {
    let task: FamilyTask
    let displayTitle: String
    let anchor: Date
    /// 同开始时间连续组的首项为 `true`；后续项用透明度占位，避免左列错位。
    let showTimeIndicator: Bool
    let forWhomAvatars: [TaskCardAvatarSource]
    let assigneeLabel: String
    let onTap: () -> Void

    private var timeText: String {
        anchor.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: ScheduleTimelineMetrics.rowSpacing) {
            timeColumn
            axisDotColumn
            cardColumn
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    // MARK: - 左：时间

    private var timeColumn: some View {
        Text(timeText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            .frame(width: ScheduleTimelineMetrics.timeColumnWidth, alignment: .trailing)
            .opacity(showTimeIndicator ? 1 : 0)
            .accessibilityHidden(showTimeIndicator == false)
    }

    // MARK: - 中：状态圆点

    private var axisDotColumn: some View {
        timelineDot(fill: statusDotColor)
            .frame(width: ScheduleTimelineMetrics.axisColumnWidth)
            .opacity(showTimeIndicator ? 1 : 0)
            .accessibilityHidden(showTimeIndicator == false)
    }

    private func timelineDot(fill: Color) -> some View {
        ScheduleTimelineAxisDot(fill: fill)
    }

    // MARK: - 右：卡片

    private var cardColumn: some View {
        TaskCardView(
            task: task,
            displayTitle: displayTitle,
            forWhomAvatars: forWhomAvatars,
            assigneeLabel: assigneeLabel
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, ScheduleTimelineMetrics.stackedRowBottomSpacing)
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

// MARK: - 此刻指示器（由 ScheduleTaskAnchorFlow 顶层 overlay 调用）

struct TaskRowNowIndicatorOverlay: View {
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
                .padding(.top, 2)
                .offset(y: capsuleOffset)

            ScheduleTimelineAxisDot(fill: .red)
                .frame(width: ScheduleTimelineMetrics.axisColumnWidth)
                .offset(y: dotCenterOffset)

            Rectangle()
                .fill(Color.red)
                .frame(height: ScheduleTimelineMetrics.nowLineHeight)
                .frame(maxWidth: .infinity)
                .offset(y: lineOffset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: containerHeight, alignment: .topLeading)
    }
}

/// 时间轴节点圆点（任务蓝点与当前时间红点共用尺寸与描边）。
struct ScheduleTimelineAxisDot: View {
    let fill: Color

    var body: some View {
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
}
