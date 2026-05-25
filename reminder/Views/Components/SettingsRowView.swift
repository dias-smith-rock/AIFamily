import SwiftUI

struct SettingsRowView: View {
    let title: String
    let systemImage: String
    let iconTint: Color
    var subtitle: String?
    var value: String?
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
                if showsSubtitle, let subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(AppTheme.FontToken.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsValue, let value, value.isEmpty == false {
                Text(value)
                    .font(AppTheme.FontToken.caption)
                    .foregroundStyle(.secondary)
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
