import SwiftUI

struct TimeZoneSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsManager

    var body: some View {
        List {
            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appSettings.displayTimeZoneIdentifier = nil
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.Settings.timezoneFollowSystem.localized)
                                .foregroundStyle(.primary)
                            Text(AppDisplayTimeZone.displayName(for: .current, locale: appSettings.appLocale))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if appSettings.displayTimeZoneIdentifier == nil {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tint)
                                .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ForEach(AppDisplayTimeZone.curatedIdentifiers, id: \.self) { identifier in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            appSettings.displayTimeZoneIdentifier = identifier
                        }
                    } label: {
                        HStack {
                            Text(AppDisplayTimeZone.displayName(forIdentifier: identifier, locale: appSettings.appLocale))
                                .foregroundStyle(.primary)
                            Spacer()
                            if appSettings.displayTimeZoneIdentifier == identifier {
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
                Text(L10n.Settings.timezoneFooter.localized)
            }
        }
        .navigationTitle(L10n.Settings.timezone.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TimeZoneSettingsView()
            .environmentObject(AppSettingsManager.shared)
    }
}
