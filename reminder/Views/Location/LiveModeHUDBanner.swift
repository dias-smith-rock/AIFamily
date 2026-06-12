import SwiftUI

struct LiveHuddleHUDBanner: View {
    @Environment(\.locale) private var locale
    let participants: [UserLocationState]
    let exitButtonTitle: LocalizedStringKey
    let isDestructiveExit: Bool
    let onExit: () -> Void

    @State private var radarPulse = false
    @State private var exitTapToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .symbolEffect(.pulse, options: .repeating, value: radarPulse)

                Text(L10n.Location.liveLocationLldOnline.formatted(locale: locale, participants.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                Button {
                    exitTapToken += 1
                    onExit()
                } label: {
                    Text(exitButtonTitle)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(isDestructiveExit ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if isDestructiveExit {
                                Capsule().fill(Color.red)
                            } else {
                                Capsule().fill(Color.primary.opacity(0.08))
                            }
                        }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .heavy), trigger: exitTapToken)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(participants) { member in
                        VStack(spacing: 4) {
                            LocationMemberAvatarView(
                                displayName: member.displayName,
                                avatarURL: member.avatarURL,
                                size: 34,
                                isGrayscale: false
                            )
                            Text(member.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 48)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.4), Color.orange.opacity(0.25)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .onAppear { radarPulse = true }
    }
}

#Preview {
    LiveHuddleHUDBanner(
        participants: UserLocationState.previewHousehold,
        exitButtonTitle: L10n.Common.leave.localized,
        isDestructiveExit: false
    ) {}
    .padding()
}
