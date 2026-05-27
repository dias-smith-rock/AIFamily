import SwiftUI
import Kingfisher

struct FamilyMemberRowView: View {
    @Environment(\.locale) private var locale

    let profile: FamilyProfile
    /// 当前行是否为 **虚拟档案**（无 `household_memberships` 关联）。
    var isVirtualUser: Bool = false
    /// 列表行内显著角色：仅传 `.creator` 或 `.admin`；普通成员传 `nil`。
    var prominentRole: MembershipRole? = nil
    var onTap: (() -> Void)? = nil
    @State private var revealsFullPhone = false

    /// 列表右侧手机号脱敏（保留末 4 位数字）。
    static func maskPhoneForDisplay(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 4 else {
            return String(repeating: "•", count: min(4, max(1, digits.count)))
        }
        if digits.count <= 4 {
            return String(repeating: "•", count: 2) + digits
        }
        return "••••" + String(digits.suffix(4))
    }

    private var mainTitle: String {
        profile.displayName
    }

    private var initialCharacter: String {
        let trimmed = mainTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first)
    }

    /// 无头像时：按成员 `id` 稳定映射到不同底色，便于区分（均为系统语义色 + 透明度，保证白字可读）。
    private static let avatarBackgroundPalette: [Color] = [
        Color.blue.opacity(0.68),
        Color.indigo.opacity(0.64),
        Color.purple.opacity(0.62),
        Color.pink.opacity(0.62),
        Color.teal.opacity(0.66),
        Color.green.opacity(0.62),
        Color.orange.opacity(0.72),
        Color.red.opacity(0.58),
        Color.brown.opacity(0.62),
        Color.cyan.opacity(0.66),
    ]

    private var avatarPaletteIndex: Int {
        let hex = profile.id.uuidString.replacingOccurrences(of: "-", with: "")
        let tail = String(hex.suffix(8))
        if let parsed = Int(tail, radix: 16) {
            return parsed % Self.avatarBackgroundPalette.count
        }
        let fallback = hex.reduce(0) { partial, character in
            partial + (character.hexDigitValue.map { $0 } ?? 0)
        }
        return fallback % Self.avatarBackgroundPalette.count
    }

    private var avatarBackground: Color {
        Self.avatarBackgroundPalette[avatarPaletteIndex]
    }

    private var contactLineDisplayText: String {
        guard let contact = profile.displayContact else {
            return AppLocalized.string("No contact info", locale: locale)
        }
        if profile.displayContactIsPhoneNumber {
            if revealsFullPhone {
                return contact
            }
            return Self.maskPhoneForDisplay(contact)
        }
        return contact
    }

    private var canTogglePhoneReveal: Bool {
        profile.displayContactIsPhoneNumber && profile.displayContact != nil
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let avatarURLString = profile.avatarUrl,
                       let avatarURL = URL(string: avatarURLString) {
                        KFImage.url(avatarURL)
                            .placeholder { ProgressView() }
                            .cacheMemoryOnly(false)
                            .resizable()
                            .scaledToFill()
                    } else {
                        avatarFallback
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(mainTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let prominentRole {
                            membershipRoleCapsule(prominentRole)
                        }

                        if isVirtualUser {
                            localProfileBadge
                        }
                    }

                    HStack(spacing: 6) {
                        Text(contactLineDisplayText)
                            .font(.caption)
                            .foregroundStyle(profile.displayContact == nil ? .tertiary : .secondary)
                            .monospacedDigit()
                            .lineLimit(1)

                        if canTogglePhoneReveal {
                            Button {
                                revealsFullPhone.toggle()
                            } label: {
                                Image(systemName: revealsFullPhone ? "eye.slash" : "eye")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var localProfileBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "icloud")
                .font(.caption2.weight(.medium))
            Text(AppLocalized.string("档案", locale: locale))
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.tertiary)
        .accessibilityLabel(AppLocalized.string("档案成员", locale: locale))
    }

    @ViewBuilder
    private func membershipRoleCapsule(_ role: MembershipRole) -> some View {
        switch role {
        case .creator:
            Text(AppLocalized.string("创建者", locale: locale))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.12))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .admin:
            Text(AppLocalized.string("管理员", locale: locale))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.14))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .member:
            EmptyView()
        }
    }

    private var avatarFallback: some View {
        Text(initialCharacter)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(avatarBackground)
    }
}
