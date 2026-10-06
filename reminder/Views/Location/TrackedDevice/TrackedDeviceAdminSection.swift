import SwiftUI

/// 编辑档案：绑定定位设备 + 创建者/管理员查看与修改 PIN。
struct TrackedDeviceAdminSection: View {
    @Environment(\.locale) private var locale

    let profile: FamilyProfile
    let config: ProfileEditView.TrackedDeviceAdminConfig
    let onBindDevice: () -> Void
    var isBoundOverride: Bool = false

    @State private var isDeviceBound: Bool
    @State private var bindingSnapshot = TrackedDeviceAdminBindingSnapshot.unbound
    @State private var storedPIN: String?
    @State private var draftPIN = TrackedDevicePINStore.defaultPIN
    @State private var revealsPIN = false
    @State private var isSavingPIN = false
    @State private var pinMessage: String?

    private let pairingService: TrackedDevicePairingService = SupabaseTrackedDevicePairingService()
    private let relativeTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    init(
        profile: FamilyProfile,
        config: ProfileEditView.TrackedDeviceAdminConfig,
        onBindDevice: @escaping () -> Void,
        isBoundOverride: Bool = false
    ) {
        self.profile = profile
        self.config = config
        self.onBindDevice = onBindDevice
        self.isBoundOverride = isBoundOverride
        _isDeviceBound = State(initialValue: config.isDeviceBound || isBoundOverride)
        if config.isDeviceBound || isBoundOverride {
            _bindingSnapshot = State(
                initialValue: TrackedDeviceAdminBindingSnapshot(
                    isBound: true,
                    nickname: nil,
                    deviceModel: nil,
                    boundAt: nil,
                    lastReportedAt: nil,
                    batteryLevel: nil,
                    isCharging: nil,
                    addressName: nil
                )
            )
        }
    }

    var body: some View {
        Section {
            LabeledContent {
                Text(
                    (isDeviceBound
                        ? L10n.Location.trackedDeviceBound
                        : L10n.Location.trackedDeviceUnbound).localized
                )
                .foregroundStyle(.secondary)
            } label: {
                Text(L10n.Location.trackedDeviceSection.localized)
            }

            if isDeviceBound {
                boundDeviceInfoRows
            }

            Button {
                Task { await bindDeviceAfterEnsuringDefaultPIN() }
            } label: {
                Label(
                    (isDeviceBound
                        ? L10n.Location.trackedRebindDeviceAction
                        : L10n.Location.trackedBindDeviceAction).localized,
                    systemImage: "iphone.and.arrow.forward"
                )
            }
            .buttonStyle(.borderless)

            HStack {
                if revealsPIN {
                    TextField(
                        AppLocalized.string(L10n.Location.trackedParentPin, locale: locale),
                        text: $draftPIN
                    )
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                } else {
                    SecureField(
                        AppLocalized.string(L10n.Location.trackedParentPin, locale: locale),
                        text: $draftPIN
                    )
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                }
                Button {
                    revealsPIN.toggle()
                } label: {
                    Image(systemName: revealsPIN ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await savePIN() }
            } label: {
                if isSavingPIN {
                    ProgressView()
                } else {
                    Text(L10n.Location.trackedSavePin.localized)
                }
            }
            .disabled(isSavingPIN || TrackedDevicePINStore.isAcceptableInput(draftPIN) == false)

            if let pinMessage {
                Text(pinMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(
                storedPIN == nil
                    ? L10n.Location.trackedPinNotSet.localized
                    : L10n.Location.trackedPinTakesEffectHint.localized
            )
        }
        .task {
            await loadPIN()
            await refreshBinding()
        }
        .task(id: isBoundOverride) {
            if isBoundOverride {
                isDeviceBound = true
            }
            await refreshBinding()
        }
    }

    @ViewBuilder
    private var boundDeviceInfoRows: some View {
        LabeledContent {
            Text(deviceModelText)
                .foregroundStyle(.secondary)
        } label: {
            Text(L10n.Location.trackedDeviceModel.localized)
        }

        LabeledContent {
            Text(boundAtText)
                .foregroundStyle(.secondary)
        } label: {
            Text(L10n.Location.trackedDeviceBoundAt.localized)
        }

        LabeledContent {
            Text(lastReportText)
                .foregroundStyle(.secondary)
        } label: {
            Text(L10n.Location.trackedShellLastReport.localized)
        }

        if let battery = bindingSnapshot.batteryLevel {
            LabeledContent {
                HStack(spacing: 4) {
                    Image(systemName: bindingSnapshot.isCharging == true ? "bolt.fill" : "battery.50percent")
                    Text("\(battery)%")
                }
                .foregroundStyle(.secondary)
            } label: {
                Text(L10n.Location.trackedShellBattery.localized)
            }
        }
    }

    private var deviceModelText: String {
        if let model = bindingSnapshot.deviceModel?.trimmingCharacters(in: .whitespacesAndNewlines),
           model.isEmpty == false {
            return model
        }
        return AppLocalized.string(L10n.Location.trackedDeviceModelUnknown, locale: locale)
    }

    private var boundAtText: String {
        guard let date = bindingSnapshot.boundAt, date > Date.distantPast.addingTimeInterval(1) else {
            return AppLocalized.string(L10n.Location.trackedDeviceBoundAtUnknown, locale: locale)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var lastReportText: String {
        guard let date = bindingSnapshot.lastReportedAt, date > Date.distantPast.addingTimeInterval(1) else {
            return AppLocalized.string(L10n.Location.trackedNoReportYet, locale: locale)
        }
        relativeTime.locale = locale
        return relativeTime.localizedString(for: date, relativeTo: Date())
    }

    @MainActor
    private func refreshBinding() async {
        TrackedDevicePairingLogger.event(
            "admin_ui_refresh_start",
            detail: "override=\(isBoundOverride) configBound=\(config.isDeviceBound) stateBound=\(isDeviceBound) household=\(config.householdId.uuidString.lowercased()) profile=\(profile.id.uuidString.lowercased())"
        )
        if isBoundOverride {
            isDeviceBound = true
        }
        do {
            let snapshot = try await pairingService.fetchAdminBindingSnapshot(
                householdId: config.householdId,
                targetProfileId: profile.id
            )
            TrackedDevicePairingLogger.event(
                "admin_ui_refresh_snapshot",
                detail: "snapshotBound=\(snapshot.isBound) override=\(isBoundOverride) nick=\(snapshot.nickname ?? "nil")"
            )
            if snapshot.isBound || isBoundOverride {
                isDeviceBound = true
                bindingSnapshot = TrackedDeviceAdminBindingSnapshot(
                    isBound: true,
                    nickname: snapshot.nickname,
                    deviceModel: snapshot.deviceModel,
                    boundAt: snapshot.boundAt,
                    lastReportedAt: snapshot.lastReportedAt,
                    batteryLevel: snapshot.batteryLevel,
                    isCharging: snapshot.isCharging,
                    addressName: snapshot.addressName
                )
                TrackedDevicePairingLogger.event("admin_ui_show_bound", detail: "reason=\(snapshot.isBound ? "snapshot" : "override")")
            } else if isBoundOverride == false {
                isDeviceBound = false
                bindingSnapshot = .unbound
                TrackedDevicePairingLogger.event("admin_ui_show_unbound", detail: "snapshot_unbound_no_override")
            }
        } catch {
            TrackedDevicePairingLogger.failure(error, stage: "admin_binding_snapshot")
            if isBoundOverride {
                isDeviceBound = true
                TrackedDevicePairingLogger.event("admin_ui_show_bound", detail: "reason=override_after_error")
            }
        }
    }

    @MainActor
    private func loadPIN() async {
        do {
            let pin = try await pairingService.fetchPIN(
                householdId: config.householdId,
                targetProfileId: profile.id
            )
            if let pin, TrackedDevicePINStore.isValidFormat(pin) {
                storedPIN = pin
                draftPIN = pin
                return
            }
            await persistPIN(TrackedDevicePINStore.defaultPIN)
        } catch {
            pinMessage = error.localizedDescription
            draftPIN = TrackedDevicePINStore.defaultPIN
        }
    }

    @MainActor
    private func bindDeviceAfterEnsuringDefaultPIN() async {
        if TrackedDevicePINStore.isValidFormat(draftPIN) == false {
            draftPIN = TrackedDevicePINStore.defaultPIN
        }
        let normalized = TrackedDevicePINStore.normalize(draftPIN)
        if storedPIN != normalized {
            await persistPIN(normalized)
        }
        onBindDevice()
    }

    @MainActor
    private func persistPIN(_ pin: String) async {
        let toWrite = TrackedDevicePINStore.isValidFormat(pin)
            ? TrackedDevicePINStore.normalize(pin)
            : TrackedDevicePINStore.defaultPIN
        draftPIN = toWrite
        do {
            try await pairingService.setPIN(
                householdId: config.householdId,
                targetProfileId: profile.id,
                pin: toWrite
            )
            storedPIN = toWrite
        } catch {
            pinMessage = error.localizedDescription
        }
    }

    @MainActor
    private func savePIN() async {
        pinMessage = nil
        isSavingPIN = true
        defer { isSavingPIN = false }
        do {
            try await pairingService.setPIN(
                householdId: config.householdId,
                targetProfileId: profile.id,
                pin: draftPIN
            )
            storedPIN = {
                let normalized = TrackedDevicePINStore.normalize(draftPIN)
                return normalized.isEmpty ? nil : normalized
            }()
            pinMessage = AppLocalized.string(L10n.Location.trackedPinTakesEffectHint, locale: locale)
        } catch {
            pinMessage = error.localizedDescription
        }
    }
}
