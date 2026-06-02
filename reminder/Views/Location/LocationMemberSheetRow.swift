import SwiftUI

struct LocationMemberSheetRow: View {
    let member: UserLocationState
    let isSelected: Bool
    let onSelectionChange: (Bool) -> Void
    @Environment(\.locale) private var locale

    private let checkboxColumnWidth: CGFloat = 32
    private let avatarSize: CGFloat = 44

    private var batterySymbol: String {
        switch member.clampedBatteryLevel {
        case 0 ... 10: "battery.0percent"
        case 11 ... 35: "battery.25percent"
        case 36 ... 60: "battery.50percent"
        case 61 ... 85: "battery.75percent"
        default: "battery.100percent"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            selectionColumn
                .frame(width: checkboxColumnWidth, height: avatarSize, alignment: .center)

            LocationMemberAvatarView(
                displayName: member.displayName,
                avatarURL: member.avatarURL,
                size: avatarSize,
                isGrayscale: member.isGhostMode
            )

            Text(titleLine)
                .font(.headline)
                .foregroundStyle(member.isGhostMode ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: avatarSize, alignment: .center)

            if member.isGhostMode == false, member.isVirtualMember == false {
                HStack(spacing: 4) {
                    Image(systemName: member.isCharging ? "bolt.fill" : batterySymbol)
                        .font(.caption)
                    Text("\(member.clampedBatteryLevel)%")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
                .frame(height: avatarSize)
            }
        }
        .frame(maxWidth: .infinity, minHeight: avatarSize, alignment: .leading)
        .opacity(member.isGhostMode ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilitySummary)
    }

    private var titleLine: String {
        if member.isGhostMode {
            return "\(member.displayName) · 👻 位置已隐藏"
        }
        if member.isVirtualMember {
            return "\(member.displayName) · 虚拟成员"
        }
        return member.displayName
    }

    private var accessibilitySummary: String {
        if member.isVirtualMember {
            return "\(member.displayName)，虚拟成员，暂无位置共享"
        }
        if member.isGhostMode {
            return "\(member.displayName)，位置已隐藏"
        }
        var parts = [member.displayName]
        if let address = member.addressDescription {
            parts.append(address)
        }
        if let lastUpdatedAt = member.lastUpdatedAt {
            parts.append(lastUpdatedText(since: lastUpdatedAt))
        }
        parts.append("电量 \(member.clampedBatteryLevel)%")
        return parts.joined(separator: "，")
    }

    @ViewBuilder
    private var selectionColumn: some View {
        if member.isVirtualMember {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.body.weight(.medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        } else if member.isGhostMode {
            Image(systemName: "location.slash")
                .font(.body.weight(.medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        } else {
            Button {
                onSelectionChange(isSelected == false)
            } label: {
                ZStack {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.blue)
                    } else {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.75), lineWidth: 2)
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground).opacity(0.6))
                            )
                            .frame(width: 22, height: 22)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "已选中" : "未选中")
        }
    }

    private func lastUpdatedText(since date: Date) -> String {
        let minutes = max(1, Int(Date().timeIntervalSince(date) / 60))
        let format = String(
            localized: "%lld 分钟前更新",
            locale: locale
        )
        return String(format: format, locale: locale, minutes)
    }
}

#Preview {
    VStack(spacing: 0) {
        LocationMemberSheetRow(
            member: UserLocationState.previewHousehold[0],
            isSelected: true,
            onSelectionChange: { _ in }
        )
        Divider()
        LocationMemberSheetRow(
            member: UserLocationState.previewHousehold[1],
            isSelected: false,
            onSelectionChange: { _ in }
        )
        Divider()
        LocationMemberSheetRow(
            member: UserLocationState.previewHousehold[2],
            isSelected: false,
            onSelectionChange: { _ in }
        )
    }
    .padding()
    .frame(width: 320)
    .background(.regularMaterial)
}
