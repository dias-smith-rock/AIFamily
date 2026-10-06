import SwiftUI

struct LocationPersistSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsManager
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap

    @AppStorage(LocationPersistPreferences.distanceStorageKey)
    private var distanceMeters = LocationPersistPreferences.defaultMinUpdateDistanceMeters
    @AppStorage(LocationPersistPreferences.intervalStorageKey)
    private var intervalSeconds = LocationPersistPreferences.defaultMinUpdateIntervalSeconds
    @AppStorage(LocationMapDisplayPreferences.displayCountStorageKey)
    private var mapHistoryDisplayCount = LocationMapDisplayPreferences.defaultHistoryDisplayCount

    @State private var isLocationGhostMode = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: locationGhostModeBinding) {
                    HStack(spacing: 6) {
                        Text(L10n.Settings.locationGhostToggle.localized)
                        proBadge
                    }
                }
                .disabled(appRouter.selectedHouseholdId == nil || appRouter.selectedProfileId == nil)
            } header: {
                Text(L10n.Settings.locationSharingSection.localized)
            } footer: {
                Text(L10n.Settings.locationGhostFooter.localized)
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
                Text(L10n.Settings.locationReportingDistanceSection.localized)
            } footer: {
                Text(L10n.Settings.locationReportingDistanceFooter.localized)
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
                Text(L10n.Settings.locationReportingIntervalSection.localized)
            } footer: {
                Text(L10n.Settings.locationReportingIntervalFooter.localized)
            }

            Section {
                ForEach(LocationMapDisplayPreferences.historyDisplayCountOptions, id: \.self) { count in
                    optionRow(
                        title: historyDisplayCountLabel(for: count),
                        isSelected: normalizedMapHistoryDisplayCount == count,
                        showsProBadge: LocationMapDisplayPreferences.isUnlimited(count)
                            || count > PremiumLimits.freeMaxMapHistoryDisplayCount
                    ) {
                        guard PremiumLimits.canSetMapHistoryDisplayCount(
                            count,
                            hasPremium: appRouter.hasPremiumAccess
                        ) else {
                            appRouter.presentPremiumUpgrade()
                            return
                        }
                        mapHistoryDisplayCount = count
                    }
                }
            } header: {
                Text(L10n.Settings.locationReportingHistoryCountSection.localized)
            } footer: {
                Text(L10n.Settings.locationReportingHistoryCountFooter.localized)
            }
        }
        .navigationTitle(L10n.Settings.locationReportingNavTitle.localized)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, appSettings.appLocale)
        .onAppear {
            distanceMeters = LocationPersistPreferences.normalizedDistance(distanceMeters)
            intervalSeconds = LocationPersistPreferences.normalizedInterval(intervalSeconds)
            clampMapHistoryDisplayCountForCurrentTier()
            syncGhostModeFromPreferences()
        }
        .onChange(of: appRouter.hasPremiumAccess) { _, _ in
            clampMapHistoryDisplayCountForCurrentTier()
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

    private var normalizedMapHistoryDisplayCount: Int {
        LocationMapDisplayPreferences.normalizedCount(mapHistoryDisplayCount)
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

        if enabled, PremiumLimits.canEnableLocationGhostMode(hasPremium: appRouter.hasPremiumAccess) == false {
            appRouter.presentPremiumUpgrade()
            return
        }

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

    private func clampMapHistoryDisplayCountForCurrentTier() {
        let clamped = PremiumLimits.clampedMapHistoryDisplayCount(
            mapHistoryDisplayCount,
            hasPremium: appRouter.hasPremiumAccess
        )
        mapHistoryDisplayCount = clamped
    }

    private func optionRow(
        title: LocalizedStringResource,
        isSelected: Bool,
        showsProBadge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                if showsProBadge {
                    proBadge
                }
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

    private var proBadge: some View {
        Text("Pro")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.orange, in: Capsule())
    }

    private func distanceLabel(for meters: Double) -> LocalizedStringResource {
        switch Int(meters) {
        case 100: L10n.Common.distance100m.localized
        case 200: L10n.Common.distance200m.localized
        case 300: L10n.Common.distance300m.localized
        case 500: L10n.Common.distance500m.localized
        case 1_000: L10n.Common.distance1km.localized
        case 2_000: L10n.Common.distance2km.localized
        default: L10n.Common.distance500m.localized
        }
    }

    private func intervalLabel(for seconds: TimeInterval) -> LocalizedStringResource {
        switch Int(seconds) {
        case 300: L10n.Common.duration5min.localized
        case 600: L10n.Common.duration10min.localized
        case 900: L10n.Common.duration15min.localized
        case 1_800: L10n.Common.duration30min.localized
        case 3_600: L10n.Common.duration1hour.localized
        default: L10n.Common.duration5min.localized
        }
    }

    private func historyDisplayCountLabel(for count: Int) -> LocalizedStringResource {
        switch count {
        case 3: L10n.Common.count3.localized
        case 5: L10n.Common.count5.localized
        case 10: L10n.Common.count10.localized
        case 20: L10n.Common.count20.localized
        case LocationMapDisplayPreferences.unlimitedHistoryDisplayCount:
            L10n.Common.unlimited.localized
        default: L10n.Common.count3.localized
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
