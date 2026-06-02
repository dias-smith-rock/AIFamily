import Kingfisher
import SwiftUI

struct LocationMemberAvatarView: View {
    let displayName: String
    let avatarURL: URL?
    var size: CGFloat = 44
    var isGrayscale: Bool = false

    var body: some View {
        Group {
            if let avatarURL {
                KFImage.url(avatarURL)
                    .placeholder { avatarPlaceholder(showProgress: true) }
                    .cacheMemoryOnly(false)
                    .resizable()
                    .scaledToFill()
            } else {
                avatarPlaceholder(showProgress: false)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .grayscale(isGrayscale ? 1 : 0)
    }

    private func avatarPlaceholder(showProgress: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemFill))
            if showProgress {
                ProgressView()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var initials: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}
