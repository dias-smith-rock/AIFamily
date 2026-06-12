import SwiftUI

struct SettingsRowView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let iconTint: Color
    var subtitle: LocalizedStringKey?
    var value: String?
    var valueKey: LocalizedStringKey?
    var showsValue: Bool = true
    var showsSubtitle: Bool = true
    var showsChevron: Bool = true

    init(
        title: LocalizedStringKey,
        systemImage: String,
        iconTint: Color,
        subtitle: LocalizedStringKey? = nil,
        value: String? = nil,
        valueKey: LocalizedStringKey? = nil,
        showsValue: Bool = true,
        showsSubtitle: Bool = true,
        showsChevron: Bool = true
    ) {
        self.title = title
        self.systemImage = systemImage
        self.iconTint = iconTint
        self.subtitle = subtitle
        self.value = value
        self.valueKey = valueKey
        self.showsValue = showsValue
        self.showsSubtitle = showsSubtitle
        self.showsChevron = showsChevron
    }

    init(
        title: L10n.Entry,
        systemImage: String,
        iconTint: Color,
        subtitle: L10n.Entry? = nil,
        value: String? = nil,
        valueKey: LocalizedStringKey? = nil,
        showsValue: Bool = true,
        showsSubtitle: Bool = true,
        showsChevron: Bool = true
    ) {
        self.init(
            title: title.localized,
            systemImage: systemImage,
            iconTint: iconTint,
            subtitle: subtitle?.localized,
            value: value,
            valueKey: valueKey,
            showsValue: showsValue,
            showsSubtitle: showsSubtitle,
            showsChevron: showsChevron
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 30, height: 30)
                .background(iconTint.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.FontToken.bodyStrong)
                    .foregroundStyle(.primary)
                if showsSubtitle, let subtitle {
                    Text(subtitle)
                        .font(AppTheme.FontToken.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsValue {
                if let valueKey {
                    Text(valueKey)
                        .font(AppTheme.FontToken.caption)
                        .foregroundStyle(.secondary)
                } else if let value, value.isEmpty == false {
                    Text(value)
                        .font(AppTheme.FontToken.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
