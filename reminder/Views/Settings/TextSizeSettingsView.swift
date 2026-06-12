import SwiftUI

struct TextSizeSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsManager

    private var sliderUpperBound: Double {
        Double(max(AppTextSize.allCases.count - 1, 0))
    }

    var body: some View {
        List {
            Section {
                previewCard
            } header: {
                Text(L10n.Common.preview.localized)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(AppTextSize.tiny.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(appSettings.appTextSize.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(AppTextSize.extraLarge.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(appSettings.appTextSize.rawValue) },
                            set: { appSettings.appTextSize = AppTextSize.fromSliderIndex(Int($0.rounded())) }
                        ),
                        in: 0...sliderUpperBound,
                        step: 1
                    )
                    .accessibilityLabel(L10n.Common.fontSize)
                    .accessibilityValue(appSettings.appTextSize.accessibilityTitle(locale: appSettings.appLocale))
                }
                .padding(.vertical, 4)
            } footer: {
                Text(L10n.Common.afterAdjustingTheFontSizeTheTextInTheAp.localized)
            }
        }
        .navigationTitle(L10n.Common.textSize.localized)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, appSettings.appLocale)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Common.weekendShoppingList.localized)
                .font(.headline)

            Text(L10n.Common.rememberToCheckYourRefrigeratorInventoryOn.localized)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.ColorToken.border, lineWidth: 1)
        )
        .dynamicTypeSize(appSettings.dynamicTypeSize)
        .animation(.easeInOut(duration: 0.2), value: appSettings.appTextSize)
    }
}

#Preview {
    NavigationStack {
        TextSizeSettingsView()
            .environmentObject(AppSettingsManager.shared)
    }
}
