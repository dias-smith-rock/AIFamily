import SwiftUI

/// 小孩机：输入 / 扫码配对码并设置家长 PIN。
struct ClaimTrackedDeviceSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter

    @Binding var pairingCode: String
    var onFinished: () -> Void

    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var step: Step = .code

    private let pairingService: TrackedDevicePairingService = SupabaseTrackedDevicePairingService()

    private enum Step {
        case code
        case pin
    }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .code:
                    Section {
                        TextField(
                            AppLocalized.string(L10n.Location.trackedEnterPairingCode, locale: locale),
                            text: $pairingCode
                        )
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title2, design: .monospaced))
                    } footer: {
                        Text(L10n.Location.trackedClaimFooter.localized)
                    }
                case .pin:
                    Section {
                        SecureField(
                            AppLocalized.string(L10n.Location.trackedSetParentPin, locale: locale),
                            text: $pin
                        )
                        .keyboardType(.numberPad)
                        SecureField(
                            AppLocalized.string(L10n.Location.trackedConfirmParentPin, locale: locale),
                            text: $confirmPIN
                        )
                        .keyboardType(.numberPad)
                    } footer: {
                        Text(L10n.Location.trackedPinFooter.localized)
                    }
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
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(primaryButtonTitle) {
                        Task { await primaryAction() }
                    }
                    .disabled(isSubmitting || primaryDisabled)
                }
            }
        }
    }

    private var primaryButtonTitle: LocalizedStringResource {
        switch step {
        case .code: L10n.Common.continueButton.localized
        case .pin: L10n.Common.finish.localized
        }
    }

    private var primaryDisabled: Bool {
        switch step {
        case .code:
            return normalizedCode.count != 6
        case .pin:
            return TrackedDevicePINStore.isValidFormat(pin) == false
                || TrackedDevicePINStore.normalize(pin) != TrackedDevicePINStore.normalize(confirmPIN)
        }
    }

    private var normalizedCode: String {
        pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    @MainActor
    private func primaryAction() async {
        errorMessage = nil
        switch step {
        case .code:
            isSubmitting = true
            defer { isSubmitting = false }
            do {
                _ = try await pairingService.claimPairingNonce(normalizedCode)
                await appRouter.refreshStateFromBackend()
                step = .pin
            } catch {
                errorMessage = error.localizedDescription
            }
        case .pin:
            TrackedDevicePINStore.savePIN(pin)
            appRouter.lockTrackedDeviceShell()
            onFinished()
            dismiss()
        }
    }
}
