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
                Text("更改主题后，应用会立即切换显示模式。")
            }
        }
        .navigationTitle("主题")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
            .environmentObject(AppSettingsManager.shared)
    }
}
