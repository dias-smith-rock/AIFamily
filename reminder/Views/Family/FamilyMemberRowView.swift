import SwiftUI

struct FamilyMemberRowView: View {
    let profile: FamilyProfile
    let subtitle: String
    var onTap: (() -> Void)? = nil
    @State private var revealsSensitiveInfo = false

    private var initialCharacter: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first)
    }

    private var avatarBackground: Color {
        let palette: [Color] = [
            Color(red: 0.95, green: 0.79, blue: 0.84),
            Color(red: 0.80, green: 0.88, blue: 0.98),
            Color(red: 0.82, green: 0.95, blue: 0.84),
            Color(red: 0.99, green: 0.90, blue: 0.75),
            Color(red: 0.88, green: 0.83, blue: 0.96)
        ]
        let index = abs(profile.id.uuidString.hashValue) % palette.count
        return palette[index]
    }

    private var sensitiveSummary: String? {
        let ids = [profile.idCardNum, profile.passportNum, profile.permitNum]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard let first = ids.first else { return nil }
        return revealsSensitiveInfo ? first : maskSensitive(first)
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let avatarURLString = profile.avatarUrl,
                       let avatarURL = URL(string: avatarURLString) {
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                avatarFallback
                            }
                        }
                    } else {
                        avatarFallback
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let sensitiveSummary {
                        HStack(spacing: 6) {
                            Text(sensitiveSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button {
                                revealsSensitiveInfo.toggle()
                            } label: {
                                Image(systemName: revealsSensitiveInfo ? "eye.slash" : "eye")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var avatarFallback: some View {
        Text(initialCharacter)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(avatarBackground)
    }

    private func maskSensitive(_ source: String) -> String {
        guard source.count > 8 else { return String(repeating: "*", count: source.count) }
        let prefix = source.prefix(3)
        let suffix = source.suffix(4)
        let stars = String(repeating: "*", count: max(0, source.count - 7))
        return "\(prefix)\(stars)\(suffix)"
    }
}
