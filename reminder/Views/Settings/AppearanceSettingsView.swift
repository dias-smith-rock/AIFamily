import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsManager

    var body: some View {
        List {
            Section {
                ForEach(AppAppearance.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            appSettings.appearance = option
                        }
                    } label: {
                        HStack {
                            Text(option.localizedName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appSettings.appearance == option {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(L10n.Common.afterChangingTheThemeTheAppSwitchesDispla.localized)
            }
        }
        .navigationTitle(L10n.Common.theme.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
            .environmentObject(AppSettingsManager.shared)
    }
}
