import SwiftUI

struct LiveHuddleLobbyCard: View {
    let participants: [UserLocationState]
    let onJoin: () -> Void

    @State private var pulse = false
    @State private var joinTapToken = 0

    var body: some View {
        HStack(spacing: 12) {
            avatarStack

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Common.liveOngoingCount.formatted(locale: locale, participants.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                joinTapToken += 1
                onJoin()
            } label: {
                Text(L10n.Common.join.localized)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green, in: Capsule())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .medium), trigger: joinTapToken)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.green.opacity(pulse ? 0.85 : 0.35), lineWidth: 1.5)
                }
        }
        .scaleEffect(pulse ? 1.01 : 0.99)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }

    private var avatarStack: some View {
        HStack(spacing: -10) {
            ForEach(Array(participants.prefix(4).enumerated()), id: \.element.id) { index, member in
                LocationMemberAvatarView(
                    displayName: member.displayName,
                    avatarURL: member.avatarURL,
                    size: 32,
                    isGrayscale: false
                )
                .overlay {
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                }
                .zIndex(Double(4 - index))
            }
        }
        .frame(width: min(88, CGFloat(participants.prefix(4).count) * 22 + 10), alignment: .leading)
    }
}

#Preview {
    LiveHuddleLobbyCard(
        participants: Array(UserLocationState.previewHousehold.prefix(3))
    ) {}
    .padding()
}
