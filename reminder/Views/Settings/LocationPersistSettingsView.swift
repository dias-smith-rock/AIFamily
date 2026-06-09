import SwiftUI

struct LocationPersistSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsManager
    @AppStorage(LocationPersistPreferences.distanceStorageKey)
    private var distanceMeters = LocationPersistPreferences.defaultMinUpdateDistanceMeters
    @AppStorage(LocationPersistPreferences.intervalStorageKey)
    private var intervalSeconds = LocationPersistPreferences.defaultMinUpdateIntervalSeconds

    var body: some View {
        List {
            Section {
                ForEach(LocationPersistPreferences.distanceOptionsMeters, id: \.self) { meters in
                    optionRow(
                        title: distanceLabel(for: meters),
                        isSelected: normalizedDistance == meters
                    ) {
                        distanceMeters = meters
                        applyPreferenceSideEffects()
                    }
                }
            } header: {
                Text("位移阈值")
            } footer: {
                Text("移动超过此距离后，才可能写入云端位置。")
            }

            Section {
                ForEach(LocationPersistPreferences.intervalOptionsSeconds, id: \.self) { seconds in
                    optionRow(
                        title: intervalLabel(for: seconds),
                        isSelected: normalizedInterval == seconds
                    ) {
                        intervalSeconds = seconds
                        applyPreferenceSideEffects()
                    }
                }
            } header: {
                Text("上报间隔")
            } footer: {
                Text("仅当位移超过所选阈值，且距上次上报超过所选间隔时，才会写入云端位置。")
            }
        }
        .navigationTitle("位置上报")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, appSettings.appLocale)
        .onAppear {
            distanceMeters = LocationPersistPreferences.normalizedDistance(distanceMeters)
            intervalSeconds = LocationPersistPreferences.normalizedInterval(intervalSeconds)
        }
    }

    private var normalizedDistance: Double {
        LocationPersistPreferences.normalizedDistance(distanceMeters)
    }

    private var normalizedInterval: TimeInterval {
        LocationPersistPreferences.normalizedInterval(intervalSeconds)
    }

    private func optionRow(
        title: LocalizedStringKey,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func distanceLabel(for meters: Double) -> LocalizedStringKey {
        switch Int(meters) {
        case 100: "100 米"
        case 200: "200 米"
        case 300: "300 米"
        case 500: "500 米"
        case 1_000: "1 千米"
        case 2_000: "2 千米"
        default: "500 米"
        }
    }

    private func intervalLabel(for seconds: TimeInterval) -> LocalizedStringKey {
        switch Int(seconds) {
        case 300: "5 分钟"
        case 600: "10 分钟"
        case 900: "15 分钟"
        case 1_800: "30 分钟"
        case 3_600: "1 小时"
        default: "15 分钟"
        }
    }

    @MainActor
    private func applyPreferenceSideEffects() {
        BackgroundLocationCoordinator.shared.applyPersistPreferences()
        ForegroundLocationPersistScheduler.shared.restartIfRunning()
    }
}

#Preview {
    NavigationStack {
        LocationPersistSettingsView()
            .environmentObject(AppSettingsManager.shared)
    }
}
