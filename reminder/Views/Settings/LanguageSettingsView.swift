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
                Text("更改语言后，应用会立即切换显示语言。")
            }
        }
        .navigationTitle("语言")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LanguageSettingsView()
            .environmentObject(AppSettingsManager.shared)
    }
}
