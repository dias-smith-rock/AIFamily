import CoreLocation
import SwiftUI

/// 儿童追踪端极简壳：无 Tab，仅状态与家长 PIN 入口。
struct TrackedDeviceShellView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var showPINUnlock = false
    @State private var pinInput = ""
    @State private var pinError: String?
    @State private var authStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus
    @State private var batteryLevel = DeviceBatteryMonitor.shared.batteryLevel
    @State private var isCharging = DeviceBatteryMonitor.shared.isCharging
    @State private var lastReportedAt: Date?

    private let locationManager = CLLocationManager()

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
                refreshStatus()
            }
        }
        .task {
            await bootstrapTrackingIfNeeded()
            refreshStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshStatus()
            }
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
                            if TrackedDevicePINStore.hasPIN {
                                if TrackedDevicePINStore.verify(pinInput) {
                                    appRouter.unlockTrackedDeviceWithPIN()
                                    showPINUnlock = false
                                } else {
                                    pinError = AppLocalized.string(L10n.Location.trackedPinIncorrect, locale: locale)
                                }
                            } else if TrackedDevicePINStore.isValidFormat(pinInput) {
                                TrackedDevicePINStore.savePIN(pinInput)
                                showPINUnlock = false
                            }
                        }
                        .disabled(TrackedDevicePINStore.isValidFormat(pinInput) == false)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var statusText: String {
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
        switch authStatus {
        case .authorizedAlways: .green
        case .authorizedWhenInUse: .orange
        default: .red
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
        authStatus = locationManager.authorizationStatus
        DeviceBatteryMonitor.shared.refresh()
        batteryLevel = DeviceBatteryMonitor.shared.batteryLevel
        isCharging = DeviceBatteryMonitor.shared.isCharging
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
    private func bootstrapTrackingIfNeeded() async {
        BackgroundLocationPreferences.setEnabled(true)
        BackgroundLocationCoordinator.shared.updateContext(
            householdId: appRouter.selectedHouseholdId,
            profileId: appRouter.selectedProfileId
        )
        await BackgroundLocationCoordinator.shared.setEnabled(true)
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }
}
