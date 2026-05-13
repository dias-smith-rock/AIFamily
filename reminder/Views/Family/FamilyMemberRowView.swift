import SwiftUI
import Kingfisher

struct FamilyMemberRowView: View {
    let profile: FamilyProfile
    /// 主标题行文案；默认用 `profile.name`（有邮箱且为绑定账号时由上层传入邮箱等）。
    var displayTitle: String? = nil
    /// 第二行说明：与行内角色胶囊互补（创建者/管理员不再重复占一行）。
    let subtitle: String
    /// 当前行是否为 **档案成员**（无 `household_memberships` 关联）；与手机号、`user_id` 无关。
    var isLocalProfile: Bool = false
    /// 列表行内显著角色：仅传 `.creator` 或 `.admin`；普通成员传 `nil`。
    var prominentRole: MembershipRole? = nil
    /// 与 `household_memberships.phone_number` 对应的脱敏展示；无则 `nil`。
    var maskedPhoneLine: String? = nil
    /// 原始手机号，用于与 `maskedPhoneLine` 配合在行内切换显示（仅在有号码时展示眼睛按钮）。
    var rawPhoneNumber: String? = nil
    var onTap: (() -> Void)? = nil
    @State private var revealsSensitiveInfo = false
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
        if let displayTitle, displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return displayTitle
        }
        return profile.name
    }

    private var initialCharacter: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var sensitiveSummary: String? {
        let ids = [profile.idCardNum, profile.passportNum, profile.permitNum]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard let first = ids.first else { return nil }
        return revealsSensitiveInfo ? first : maskSensitive(first)
    }

    private var phoneLineText: String? {
        guard let maskedPhoneLine else { return nil }
        if revealsFullPhone, let raw = rawPhoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false {
            return raw
        }
        return maskedPhoneLine
    }

    private var canTogglePhoneReveal: Bool {
        guard let raw = rawPhoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return false
        }
        return maskedPhoneLine != nil
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

                        if isLocalProfile {
                            localProfileBadge
                        }
                    }

                    if subtitle.isEmpty == false {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let phoneLineText {
                        HStack(spacing: 6) {
                            Text(phoneLineText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
            Text("档案")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.tertiary)
        .accessibilityLabel("档案成员")
    }

    @ViewBuilder
    private func membershipRoleCapsule(_ role: MembershipRole) -> some View {
        switch role {
        case .creator:
            Text("创建者")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.12))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .admin:
            Text("管理员")
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

    private func maskSensitive(_ source: String) -> String {
        guard source.count > 8 else { return String(repeating: "*", count: source.count) }
        let prefix = source.prefix(3)
        let suffix = source.suffix(4)
        let stars = String(repeating: "*", count: max(0, source.count - 7))
        return "\(prefix)\(stars)\(suffix)"
    }
}
