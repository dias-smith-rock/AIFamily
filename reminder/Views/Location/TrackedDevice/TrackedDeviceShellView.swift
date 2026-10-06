import CoreLocation
import SwiftUI

/// 儿童追踪端极简壳：无 Tab，仅状态与家长 PIN 入口。
struct TrackedDeviceShellView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @Environment(\.scenePhase) private var scenePhase

    @State private var showPINUnlock = false
    @State private var pinInput = ""
    @State private var pinError: String?
    @State private var authStatus: CLAuthorizationStatus = LocationAuthorizationRequester.shared.authorizationStatus
    @State private var locationServicesOn = CLLocationManager.locationServicesEnabled()
    @State private var batteryLevel = DeviceBatteryMonitor.shared.batteryLevel
    @State private var isCharging = DeviceBatteryMonitor.shared.isCharging
    @State private var lastReportedAt: Date?
    @State private var showOpenSettingsAlert = false
    @State private var settingsGuidanceIsServicesOff = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent {
                        Text(appRouter.selectedHouseholdName ?? "—")
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(L10n.Location.trackedShellGroup.localized)
                    }
                    LabeledContent {
                        Text(statusText)
                            .foregroundStyle(statusColor)
                    } label: {
                        Text(L10n.Location.trackedShellLocationStatus.localized)
                    }
                    LabeledContent {
                        Text(backgroundStatusText)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(L10n.Location.trackedShellBackground.localized)
                    }
                    LabeledContent {
                        HStack(spacing: 4) {
                            Image(systemName: isCharging ? "bolt.fill" : "battery.50percent")
                            Text("\(batteryLevel)%")
                        }
                        .foregroundStyle(.secondary)
                    } label: {
                        Text(L10n.Location.trackedShellBattery.localized)
                    }
                    LabeledContent {
                        Text(lastReportedText)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(L10n.Location.trackedShellLastReport.localized)
                    }
                } footer: {
                    Text(L10n.Location.trackedShellFooter.localized)
                }

                Section {
                    Button {
                        pinInput = ""
                        pinError = nil
                        showPINUnlock = true
                    } label: {
                        Label(
                            (TrackedDevicePINStore.hasPIN
                                ? L10n.Location.trackedUnlockWithPin
                                : L10n.Location.trackedSetParentPin).localized,
                            systemImage: TrackedDevicePINStore.hasPIN ? "lock.open" : "lock.badge.clock"
                        )
                    }
                }
            }
            .navigationTitle(L10n.Location.trackedShellTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await bootstrapTrackingIfNeeded()
            }
        }
        .task {
            await TrackedDevicePINSync.applyFromServer()
            try? await SupabaseTrackedDevicePairingService().reportOwnDeviceModel(TrackedDeviceHardware.marketingName)
            appRouter.refreshTrackedDeviceShellAfterPINSync()
            await bootstrapTrackingIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await TrackedDevicePINSync.applyFromServer()
                    try? await SupabaseTrackedDevicePairingService().reportOwnDeviceModel(TrackedDeviceHardware.marketingName)
                    appRouter.refreshTrackedDeviceShellAfterPINSync()
                    await bootstrapTrackingIfNeeded()
                }
            }
        }
        .alert(L10n.Location.trackedLocationNeededTitle, isPresented: $showOpenSettingsAlert) {
            Button(L10n.Location.trackedOpenSettings) {
                SystemSettingsHelper.openAppSettings()
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(
                (settingsGuidanceIsServicesOff
                    ? L10n.Location.trackedLocationServicesOffMessage
                    : L10n.Location.trackedLocationNeededMessage).localized
            )
        }
        .sheet(isPresented: $showPINUnlock) {
            NavigationStack {
                Form {
                    Section {
                        SecureField(
                            AppLocalized.string(L10n.Location.trackedEnterParentPin, locale: locale),
                            text: $pinInput
                        )
                        .keyboardType(.numberPad)
                    } footer: {
                        Text(L10n.Location.trackedUnlockMessage.localized)
                    }
                    if let pinError {
                        Section {
                            Text(pinError)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }
                }
                .navigationTitle(L10n.Location.trackedUnlockWithPin.localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.cancel) { showPINUnlock = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.Common.ok) {
                            Task { await confirmPINUnlock() }
                        }
                        .disabled(
                            TrackedDevicePINStore.hasPIN
                                ? TrackedDevicePINStore.isValidFormat(pinInput) == false
                                : TrackedDevicePINStore.isAcceptableInput(pinInput) == false
                        )
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var statusText: String {
        if locationServicesOn == false {
            return AppLocalized.string(L10n.Location.trackedAuthServicesOff, locale: locale)
        }
        switch authStatus {
        case .authorizedAlways:
            return AppLocalized.string(L10n.Location.trackedAuthAlways, locale: locale)
        case .authorizedWhenInUse:
            return AppLocalized.string(L10n.Location.trackedAuthWhenInUse, locale: locale)
        case .denied, .restricted:
            return AppLocalized.string(L10n.Location.trackedAuthDenied, locale: locale)
        default:
            return AppLocalized.string(L10n.Location.trackedAuthNeeded, locale: locale)
        }
    }

    private var statusColor: Color {
        if locationServicesOn == false {
            return Color.red
        }
        switch authStatus {
        case .authorizedAlways: return Color.green
        case .authorizedWhenInUse: return Color.orange
        default: return Color.red
        }
    }

    private var backgroundStatusText: String {
        if BackgroundLocationPreferences.isEnabled, authStatus == .authorizedAlways {
            return AppLocalized.string(L10n.Location.trackedBackgroundOn, locale: locale)
        }
        return AppLocalized.string(L10n.Location.trackedBackgroundOff, locale: locale)
    }

    private var lastReportedText: String {
        guard let lastReportedAt else {
            return AppLocalized.string(L10n.Location.trackedNoReportYet, locale: locale)
        }
        return LocationRelativeTimeFormatting.mapBadgeText(since: lastReportedAt, locale: locale)
    }

    private func refreshStatus() {
        locationServicesOn = CLLocationManager.locationServicesEnabled()
        authStatus = LocationAuthorizationRequester.shared.authorizationStatus
        DeviceBatteryMonitor.shared.refresh()
        batteryLevel = DeviceBatteryMonitor.shared.batteryLevel
        isCharging = DeviceBatteryMonitor.shared.isCharging
        TrackedDevicePairingLogger.event(
            "loc_shell_status",
            detail: LocationAuthorizationRequester.shared.probeDetail(
                extra: "uiAuth=\(LocationAuthorizationRequester.statusName(authStatus)) servicesOn=\(locationServicesOn) bgText=\(backgroundStatusText) \(BackgroundLocationCoordinator.shared.debugSnapshot)"
            )
        )
        guard let profileId = appRouter.selectedProfileId,
              let householdId = appRouter.selectedHouseholdId else { return }
        Task {
            if let states = await HouseholdLocalCache.loadLocationStates(for: householdId),
               let mine = states.first(where: { $0.profileId == profileId }) {
                lastReportedAt = mine.latestLocation?.recordedAt ?? mine.updatedAt
            }
        }
    }

    @MainActor
    private func confirmPINUnlock() async {
        pinError = nil
        await TrackedDevicePINSync.applyFromServer()
        appRouter.refreshTrackedDeviceShellAfterPINSync()
        if TrackedDevicePINStore.hasPIN {
            if TrackedDevicePINStore.verify(pinInput) {
                appRouter.unlockTrackedDeviceWithPIN()
                showPINUnlock = false
            } else {
                pinError = AppLocalized.string(L10n.Location.trackedPinIncorrect, locale: locale)
            }
            return
        }
        guard TrackedDevicePINStore.isAcceptableInput(pinInput) else { return }
        TrackedDevicePINStore.savePIN(pinInput)
        try? await SupabaseTrackedDevicePairingService().reportOwnPIN(pinInput)
        appRouter.refreshTrackedDeviceShellAfterPINSync()
        showPINUnlock = false
    }

    @MainActor
    private func bootstrapTrackingIfNeeded() async {
        TrackedDevicePairingLogger.event(
            "loc_shell_bootstrap",
            detail: LocationAuthorizationRequester.shared.probeDetail(
                extra: "household=\(appRouter.selectedHouseholdId?.uuidString ?? "nil") profile=\(appRouter.selectedProfileId?.uuidString ?? "nil")"
            )
        )
        BackgroundLocationPreferences.setEnabled(true)
        BackgroundLocationCoordinator.shared.configure(
            locationStateService: appBootstrap.services.locationStateService
        )
        BackgroundLocationCoordinator.shared.updateContext(
            householdId: appRouter.selectedHouseholdId,
            profileId: appRouter.selectedProfileId
        )
        let result = await LocationAuthorizationRequester.shared.ensureTrackedDeviceAccess()
        await BackgroundLocationCoordinator.shared.setEnabled(true)
        if result == .always || result == .whenInUse {
            if let reportedAt = await BackgroundLocationCoordinator.shared.reportImmediateLaunchLocation() {
                lastReportedAt = reportedAt
            }
        }
        refreshStatus()
        switch result {
        case .always:
            showOpenSettingsAlert = false
        case .servicesOff:
            settingsGuidanceIsServicesOff = true
            showOpenSettingsAlert = true
        case .whenInUse, .denied, .restricted:
            settingsGuidanceIsServicesOff = false
            showOpenSettingsAlert = true
        case .notDetermined:
            break
        }
    }
}
