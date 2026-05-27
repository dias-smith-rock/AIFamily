import SwiftUI
import Kingfisher

// MARK: - 头像数据源（列表层解析后传入，避免卡片内发请求）

struct TaskCardAvatarSource: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let imageURL: URL?
}

// MARK: - 为了谁（右侧展示）

struct TaskCardForWhomTrailing: View {
    enum Style {
        case compact
        case standard
    }

    let sources: [TaskCardAvatarSource]
    var style: Style = .standard

    private var avatarSize: CGFloat {
        style == .compact ? 22 : 24
    }

    var body: some View {
        Group {
            if sources.isEmpty {
                Text("—")
                    .font(style == .compact ? .caption2 : .caption)
                    .foregroundStyle(.tertiary)
            } else if sources.count == 1, style == .compact {
                singleLabelOrAvatar(sources[0])
            } else {
                HStack(spacing: style == .compact ? -6 : -8) {
                    ForEach(Array(sources.prefix(3))) { source in
                        TaskCardOverlappingAvatar(source: source, size: avatarSize)
                    }
                }
            }
        }
        .frame(minWidth: style == .compact ? 28 : 32, alignment: .trailing)
    }

    @ViewBuilder
    private func singleLabelOrAvatar(_ source: TaskCardAvatarSource) -> some View {
        if source.imageURL != nil {
            TaskCardOverlappingAvatar(source: source, size: avatarSize)
        } else {
            Text(source.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - TaskCardView

/// 日程列表中的单条任务卡片（设计稿：左侧强调线 + 分区信息 + 右侧「为了谁」）。
struct TaskCardView: View {
    @Environment(\.locale) private var locale
    let task: FamilyTask
    let forWhomAvatars: [TaskCardAvatarSource]
    let assigneeLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    headerRow
                    metaRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TaskCardForWhomTrailing(sources: forWhomAvatars)
                    .padding(.trailing, 2)
            }

            if let place = locationDisplayName {
                locationRow(place: place)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.taskCardLeadingAccent(fromHex: task.backgroundColor))
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text(task.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(statusTitle)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(statusCapsuleForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusCapsuleBackground)
                .clipShape(Capsule())
        }
    }

    private var statusTitle: String {
        switch task.status {
        case .new: return AppLocalized.string("待接受", locale: locale)
        case .accepted: return AppLocalized.string("已接受", locale: locale)
        case .inProgress: return AppLocalized.string("进行中", locale: locale)
        case .completed: return AppLocalized.string("已完成", locale: locale)
        case .issue: return AppLocalized.string("有问题", locale: locale)
        case .expired: return AppLocalized.string("已过期", locale: locale)
        case .failed: return AppLocalized.string("失败", locale: locale)
        case .cancelled: return AppLocalized.string("已取消", locale: locale)
        }
    }

    private var statusCapsuleBackground: Color {
        switch task.status {
        case .new:
            return Color.accentColor.opacity(0.15)
        case .accepted, .inProgress:
            return Color.orange.opacity(0.15)
        case .completed:
            return Color.green.opacity(0.15)
        case .issue, .expired, .failed, .cancelled:
            return Color.red.opacity(0.12)
        }
    }

    private var statusCapsuleForeground: Color {
        switch task.status {
        case .new:
            return Color.accentColor
        case .accepted, .inProgress:
            return Color.orange
        case .completed:
            return Color.green
        case .issue, .expired, .failed, .cancelled:
            return Color.red
        }
    }

    // MARK: - Meta

    private var metaRow: some View {
        HStack(spacing: 8) {
            Label(metaTimeText, systemImage: task.isAllDay ? "calendar" : "clock")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            TaskDurationBadge(minutes: task.durationMinutes)

            Spacer(minLength: 0)
        }
    }

    private var metaTimeText: String {
        let date = task.dueDate ?? task.originalDueDate ?? task.createdAt
        if task.isAllDay {
            return date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var locationDisplayName: String? {
        let name = task.locationData?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = task.locationData?.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, name.isEmpty == false { return name }
        if let address, address.isEmpty == false { return address }
        return nil
    }

    // MARK: - 地点

    private func locationRow(place: String) -> some View {
        HStack(alignment: .center) {
            Label(place, systemImage: "mappin.and.ellipse")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 叠层头像

struct TaskCardOverlappingAvatar: View {
    let source: TaskCardAvatarSource
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            if let url = source.imageURL {
                KFImage.url(url)
                    .placeholder { Circle().fill(Color(.secondarySystemFill)) }
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color(.secondarySystemFill))
                    .overlay {
                        Text(String(source.displayName.prefix(1)))
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(.primary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white, lineWidth: 1.5)
        }
    }
}

#Preview("任务卡片") {
    TaskCardView(
        task: FamilyTask.mockTasks[0],
        forWhomAvatars: [
            TaskCardAvatarSource(
                id: UUID(uuidString: "A1111111-1111-1111-1111-111111111111") ?? UUID(),
                displayName: "老大",
                imageURL: nil
            ),
            TaskCardAvatarSource(
                id: UUID(uuidString: "B2222222-2222-2222-2222-222222222222") ?? UUID(),
                displayName: "美美",
                imageURL: nil
            )
        ],
        assigneeLabel: "张老师"
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
