import SwiftUI

struct LocationMemberSheetRow: View {
    let member: UserLocationState
    let isSelected: Bool
    let isInLiveHuddle: Bool
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

            VStack(alignment: .leading, spacing: 2) {
                Text(titleLine)
                    .font(.headline)
                    .foregroundStyle(member.isGhostMode || member.isLikelyOffline ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isInLiveHuddle == false, member.isGhostMode == false {
                    Text(subtitleLine)
                        .font(.caption)
                        .foregroundStyle(member.isLikelyOffline ? Color.orange : .secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: avatarSize, alignment: .center)

            if isInLiveHuddle {
                LiveTrackingBadge()
                    .frame(minWidth: 44, alignment: .trailing)
                    .frame(height: avatarSize)
            } else if member.isGhostMode == false,
                      member.isVirtualMember == false || member.currentLocation != nil {
                HStack(spacing: 4) {
                    Image(systemName: member.isCharging ? "bolt.fill" : batterySymbol)
                        .font(.caption)
                    Text("\(member.clampedBatteryLevel)%")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(member.isLikelyOffline ? Color.orange.opacity(0.85) : .secondary)
                .frame(minWidth: 44, alignment: .trailing)
                .frame(height: avatarSize)
            }
        }
        .frame(maxWidth: .infinity, minHeight: avatarSize, alignment: .leading)
        .opacity(member.isGhostMode ? 0.55 : (member.isLikelyOffline ? 0.72 : 1))
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilitySummary)
    }

    private var titleLine: String {
        if isInLiveHuddle {
            return String(
                format: L10n.Common.live.string(locale: locale),
                locale: locale,
                member.displayName
            )
        }
        if member.isGhostMode {
            return String(
                format: L10n.Location.locationHidden.string(locale: locale),
                locale: locale,
                member.displayName
            )
        }
        return member.displayName
    }

    private var subtitleLine: String {
        if member.isLikelyOffline {
            return AppLocalized.string(L10n.Location.trackedPossiblyOffline, locale: locale)
        }
        if let lastUpdatedAt = member.currentLocationUpdatedAt {
            return lastUpdatedText(since: lastUpdatedAt)
        }
        return AppLocalized.string(L10n.Location.trackedNoReportYet, locale: locale)
    }

    private var accessibilitySummary: String {
        if member.isVirtualMember {
            if member.currentLocation != nil {
                return String(
                    format: L10n.Location.shownOnTheMapWhenSelected.string(locale: locale),
                    locale: locale,
                    member.displayName
                )
            }
            return String(
                format: AppLocalized.string(L10n.Location.noLocationYetWillAppearOnTheMapWhenLoca, locale: locale),
                locale: locale,
                member.displayName
            )
        }
        if member.isGhostMode {
            return String(
                format: L10n.Location.locationHidden2.string(locale: locale),
                locale: locale,
                member.displayName
            )
        }
        var parts = [member.displayName]
        if let address = member.addressDescription {
            parts.append(address)
        }
        if let lastUpdatedAt = member.lastUpdatedAt {
            parts.append(lastUpdatedText(since: lastUpdatedAt))
        }
        parts.append(
            String(
                format: L10n.Common.batteryLld.string(locale: locale),
                locale: locale,
                member.clampedBatteryLevel
            )
        )
        return parts.joined(separator: "，")
    }

    @ViewBuilder
    private var selectionColumn: some View {
        if member.isGhostMode {
            Image(systemName: "location.slash")
                .font(.body.weight(.medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        } else {
            memberSelectionToggle
        }
    }

    private var memberSelectionToggle: some View {
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
        .accessibilityLabel(
            isSelected
                ? L10n.Common.selected.string(locale: locale)
                : L10n.Common.notSelected.string(locale: locale)
        )
    }

    private func lastUpdatedText(since date: Date) -> String {
        let minutes = max(1, Int(Date().timeIntervalSince(date) / 60))
        let format = AppLocalized.string(L10n.Common.updatedLldMinAgo, locale: locale)
        return String(format: format, locale: locale, minutes)
    }
}

#Preview {
    VStack(spacing: 0) {
        LocationMemberSheetRow(
            member: UserLocationState.previewHousehold[0],
            isSelected: true,
            isInLiveHuddle: false,
            onSelectionChange: { _ in }
        )
        Divider()
        LocationMemberSheetRow(
            member: UserLocationState.previewHousehold[1],
            isSelected: false,
            isInLiveHuddle: true,
            onSelectionChange: { _ in }
        )
        Divider()
        LocationMemberSheetRow(
            member: UserLocationState.previewHousehold[2],
            isSelected: false,
            isInLiveHuddle: false,
            onSelectionChange: { _ in }
        )
        Divider()
        LocationMemberSheetRow(
            member: UserLocationState.previewHousehold[3],
            isSelected: false,
            isInLiveHuddle: false,
            onSelectionChange: { _ in }
        )
    }
    .padding()
    .frame(width: 320)
    .background(.regularMaterial)
}
