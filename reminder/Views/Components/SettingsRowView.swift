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
