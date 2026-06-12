import SwiftUI
import Kingfisher

/// 全天任务紧凑卡片：仅两行——标题 + 「为了谁」头像区；左侧贴边色条与整卡圆角一体。
struct AllDayTaskRowView: View {
    let task: FamilyTask
    let displayTitle: String
    let forWhomAvatars: [TaskCardAvatarSource]

    init(
        task: FamilyTask,
        displayTitle: String? = nil,
        forWhomAvatars: [TaskCardAvatarSource]
    ) {
        self.task = task
        self.displayTitle = displayTitle ?? task.title
        self.forWhomAvatars = forWhomAvatars
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(cardTitleText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(L10n.Common.forLabel.localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if forWhomAvatars.isEmpty == false {
                    HStack(spacing: -6) {
                        ForEach(Array(forWhomAvatars.prefix(3))) { source in
                            microAvatar(source: source)
                        }
                    }
                } else {
                    Text(verbatim: "—")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.taskCardLeadingAccent(fromHex: task.backgroundColor))
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private var cardTitleText: String {
        guard task.status == .completed else { return displayTitle }
        return "✅ \(displayTitle)"
    }

    private func microAvatar(source: TaskCardAvatarSource) -> some View {
        ZStack {
            if let url = source.imageURL {
                KFImage.url(url)
                    .placeholder { Circle().fill(Color(.tertiarySystemFill)) }
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        Text(String(source.displayName.prefix(1)))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color(.systemBackground), lineWidth: 1.5)
        }
    }
}
