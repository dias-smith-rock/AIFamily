import SwiftUI
import PhotosUI
import CoreImage

/// 小孩机：输入 / 扫码配对码。PIN 由管理员设置，核销后从服务端同步。
struct ClaimTrackedDeviceSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap

    @Binding var pairingCode: String
    var onFinished: () -> Void

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showPairingSuccess = false
    @State private var showScanOptions = false
    @State private var showCameraScanner = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    private let pairingService: TrackedDevicePairingService = SupabaseTrackedDevicePairingService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        AppLocalized.string(L10n.Location.trackedEnterPairingCode, locale: locale),
                        text: $pairingCode
                    )
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.title2, design: .monospaced))
                    .disabled(isSubmitting)

                    Button {
                        showScanOptions = true
                    } label: {
                        Label(
                            L10n.Location.trackedScanQr.localized,
                            systemImage: "qrcode.viewfinder"
                        )
                    }
                    .disabled(isSubmitting)
                } footer: {
                    Text(L10n.Location.trackedClaimFooter.localized)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(L10n.Location.trackedClaimTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.cancel) { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.continueButton) {
                        Task { await claimCurrentCode() }
                    }
                    .disabled(isSubmitting || normalizedCode.count != 6)
                }
            }
            .confirmationDialog(
                L10n.Common.selectIdentificationMethod.localized,
                isPresented: $showScanOptions,
                titleVisibility: .visible
            ) {
                Button(L10n.Common.cameraScanCode) {
                    showCameraScanner = true
                }
                Button(L10n.Common.library) {
                    showPhotoPicker = true
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            }
            .forcesNonPopoverDialogPresentation()
            .fullScreenCover(isPresented: $showCameraScanner) {
                OrganizationJoinQRScannerContainer { raw in
                    applyScannedPayload(raw)
                    showCameraScanner = false
                } onError: { message in
                    errorMessage = message
                    showCameraScanner = false
                }
                .environment(\.locale, locale)
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItem,
                matching: .images,
                preferredItemEncoding: .automatic
            )
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task { await decodePairingCodeFromPhoto(newItem) }
            }
            .task {
                if normalizedCode.count == 6 {
                    await claimCurrentCode()
                }
            }
            .alert(L10n.Location.trackedPairingSuccess, isPresented: $showPairingSuccess) {
                Button(L10n.Common.ok) {
                    Task { await finishAfterSuccess() }
                }
            } message: {
                Text(L10n.Location.trackedPairingSuccessMessage.localized)
            }
        }
    }

    private var normalizedCode: String {
        TrackedDevicePairingCode.parse(pairingCode)
            ?? pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    @MainActor
    private func applyScannedPayload(_ raw: String) {
        guard let code = TrackedDevicePairingCode.parse(raw) else {
            errorMessage = AppLocalized.string(L10n.Location.trackedNoValidPairingCode, locale: locale)
            return
        }
        pairingCode = code
        errorMessage = nil
        Task { await claimCurrentCode() }
    }

    @MainActor
    private func decodePairingCodeFromPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhotoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let ciImage = CIImage(data: data) else {
                errorMessage = AppLocalized.string(L10n.Family.qrImageReadFailed, locale: locale)
                return
            }
            let detector = CIDetector(
                ofType: CIDetectorTypeQRCode,
                context: nil,
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
            )
            let features = detector?.features(in: ciImage) as? [CIQRCodeFeature]
            let payload = features?.compactMap(\.messageString).joined(separator: " ") ?? ""
            applyScannedPayload(payload)
        } catch {
            errorMessage = AppLocalized.string(L10n.Common.qrRecognitionFailedRetry, locale: locale)
        }
    }

    @MainActor
    private func claimCurrentCode() async {
        guard isSubmitting == false, normalizedCode.count == 6 else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        TrackedDevicePairingLogger.event("ui_claim_tap", code: normalizedCode)
        do {
            _ = try await pairingService.claimPairingNonce(normalizedCode)
            TrackedDevicePairingLogger.event("ui_claim_rpc_ok", code: normalizedCode)
            await TrackedDevicePINSync.applyFromServer()
            TrackedDevicePairingLogger.event("ui_pin_sync_done", code: normalizedCode)
            await appRouter.refreshStateFromBackend()
            TrackedDevicePairingLogger.event("ui_refresh_done", code: normalizedCode)
            appRouter.lockTrackedDeviceShell()
            appRouter.refreshTrackedDeviceShellAfterPINSync()
            showPairingSuccess = true
        } catch {
            TrackedDevicePairingLogger.failure(error, stage: "ui_claim", code: normalizedCode)
            errorMessage = TrackedDevicePairingLogger.userFacingMessage(error)
        }
    }

    @MainActor
    private func finishAfterSuccess() async {
        _ = await LocationAuthorizationRequester.shared.requestAlwaysForTrackedDeviceIfNeeded()
        BackgroundLocationPreferences.setEnabled(true)
        BackgroundLocationCoordinator.shared.configure(
            locationStateService: appBootstrap.services.locationStateService
        )
        BackgroundLocationCoordinator.shared.updateContext(
            householdId: appRouter.selectedHouseholdId,
            profileId: appRouter.selectedProfileId
        )
        await BackgroundLocationCoordinator.shared.setEnabled(true)
        _ = await BackgroundLocationCoordinator.shared.reportImmediateLaunchLocation()
        onFinished()
        dismiss()
    }
}
