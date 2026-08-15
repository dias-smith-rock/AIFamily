import SwiftUI
import Kingfisher

/// 全天任务紧凑卡片：暗色铺底，组织主题色为左侧强调条与头像描边。
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
                .foregroundStyle(.white)
                .lineLimit(1)

            if forWhomAvatars.isEmpty == false {
                HStack(spacing: 8) {
                    Text(L10n.Common.forLabel.localized)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.55))

                    Spacer(minLength: 0)

                    HStack(spacing: -6) {
                        ForEach(Array(forWhomAvatars.prefix(3))) { source in
                            microAvatar(source: source)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskCardSurface(for: task, cornerRadius: 10)
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
    }

    private var cardTitleText: String {
        guard task.status == .completed else { return displayTitle }
        return "✅ \(displayTitle)"
    }

    private func microAvatar(source: TaskCardAvatarSource) -> some View {
        ZStack {
            if let url = source.imageURL {
                KFImage.url(url)
                    .placeholder { Circle().fill(Color.white.opacity(0.25)) }
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .overlay {
                        Text(String(source.displayName.prefix(1)))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(task.cardThemeAccentColor, lineWidth: 1.5)
        }
    }
}
