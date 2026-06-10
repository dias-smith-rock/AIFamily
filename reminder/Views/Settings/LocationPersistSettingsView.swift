import SwiftUI

struct LocationPersistSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsManager
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap

    @AppStorage(LocationPersistPreferences.distanceStorageKey)
    private var distanceMeters = LocationPersistPreferences.defaultMinUpdateDistanceMeters
    @AppStorage(LocationPersistPreferences.intervalStorageKey)
    private var intervalSeconds = LocationPersistPreferences.defaultMinUpdateIntervalSeconds

    @State private var isLocationGhostMode = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: locationGhostModeBinding) {
                    Text("位置隐身")
                }
                .disabled(appRouter.selectedHouseholdId == nil || appRouter.selectedProfileId == nil)
            } header: {
                Text("位置共享")
            } footer: {
                Text("隐身期间不会向服务器上报新坐标，群组成员仍可看到您上次上报的位置。")
            }

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
                Text("位移与间隔均达标时会新增一条位置记录；仅间隔到达而位移未达阈值时，会更新最近一条位置记录。")
            }
        }
        .navigationTitle("位置上报")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, appSettings.appLocale)
        .onAppear {
            distanceMeters = LocationPersistPreferences.normalizedDistance(distanceMeters)
            intervalSeconds = LocationPersistPreferences.normalizedInterval(intervalSeconds)
            syncGhostModeFromPreferences()
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, _ in
            syncGhostModeFromPreferences()
        }
        .onChange(of: appRouter.selectedProfileId) { _, _ in
            syncGhostModeFromPreferences()
        }
    }

    private var locationGhostModeBinding: Binding<Bool> {
        Binding(
            get: { isLocationGhostMode },
            set: { newValue in
                setLocationGhostMode(newValue)
            }
        )
    }

    private var normalizedDistance: Double {
        LocationPersistPreferences.normalizedDistance(distanceMeters)
    }

    private var normalizedInterval: TimeInterval {
        LocationPersistPreferences.normalizedInterval(intervalSeconds)
    }

    private func syncGhostModeFromPreferences() {
        guard let householdId = appRouter.selectedHouseholdId,
              let profileId = appRouter.selectedProfileId else {
            isLocationGhostMode = false
            return
        }
        isLocationGhostMode = LocationGhostPreferences.isEnabled(
            householdId: householdId,
            profileId: profileId
        )
    }

    private func setLocationGhostMode(_ enabled: Bool) {
        guard let householdId = appRouter.selectedHouseholdId,
              let profileId = appRouter.selectedProfileId else { return }
        guard isLocationGhostMode != enabled else { return }

        LocationGhostPreferences.setEnabled(enabled, householdId: householdId, profileId: profileId)
        isLocationGhostMode = enabled

        guard enabled == false,
              let householdId = appRouter.selectedHouseholdId else { return }

        Task {
            await clearLegacyServerGhostFlagIfNeeded(householdId: householdId, profileId: profileId)
            _ = await LocationStartupReporter.report(
                trigger: .appEnteredForeground,
                householdId: householdId,
                profileId: profileId,
                locationStateService: appBootstrap.services.locationStateService
            )
        }
    }

    private func clearLegacyServerGhostFlagIfNeeded(householdId: UUID, profileId: UUID) async {
        do {
            let record = try await appBootstrap.services.locationStateService.fetchLocationState(
                householdId: householdId,
                profileId: profileId
            )
            guard record?.isGhostMode == true else { return }
            _ = try await appBootstrap.services.locationStateService.updateGhostMode(
                householdId: householdId,
                profileId: profileId,
                isGhostMode: false
            )
        } catch {
            #if DEBUG
            print("[LocationPersistSettingsView] clear legacy server ghost skipped: \(error.localizedDescription)")
            #endif
        }
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
        default: "5 分钟"
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
            .environmentObject(AppRouter())
            .environmentObject(AppBootstrap())
    }
}
