import SwiftUI

struct LanguageSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsManager

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            appSettings.selectedLanguage = language
                        }
                    } label: {
                        HStack {
                            Text(language.nativeName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appSettings.selectedLanguage == language {
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
                Text(L10n.Common.languageChangesApplyInstantlyAcrossTheApp.localized)
            }
        }
        .navigationTitle(L10n.Common.language.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LanguageSettingsView()
            .environmentObject(AppSettingsManager.shared)
    }
}
