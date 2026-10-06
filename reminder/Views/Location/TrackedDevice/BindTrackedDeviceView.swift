import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// 家长端：为指定档案生成儿童设备配对码 / 二维码。
struct BindTrackedDeviceView: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter

    let profile: FamilyProfile
    let householdId: UUID
    let managerMembershipId: UUID

    @State private var pairingCode: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let pairingService: TrackedDevicePairingService = SupabaseTrackedDevicePairingService()
    private let qrContext = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text(L10n.Location.trackedBindTitle.localized)
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(
                        L10n.Location.trackedBindSubtitle.formatted(
                            locale: locale,
                            profile.displayName
                        )
                    )
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Spacer()

                if isLoading {
                    ProgressView(AppLocalized.string(L10n.Location.trackedGeneratingCode, locale: locale))
                } else if let pairingCode {
                    VStack(spacing: 16) {
                        qrCodeCard(from: "wefamily://track?code=\(pairingCode)")
                        Text(formattedCode(pairingCode))
                            .font(.system(.largeTitle, design: .monospaced).bold())
                            .tracking(1.2)
                        Text(L10n.Location.trackedCodeExpiresHint.localized)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(errorMessage ?? AppLocalized.string(L10n.Location.trackedPairingBackendRequired, locale: locale))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }

                Spacer()

                Text(L10n.Location.trackedPinSetupHint.localized)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.finish) { dismiss() }
                }
            }
        }
        .task {
            await generateCode()
        }
    }

    private func formattedCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    @ViewBuilder
    private func qrCodeCard(from payload: String) -> some View {
        if let image = makeQRImage(from: payload) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func makeQRImage(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        qrFilter.message = data
        qrFilter.correctionLevel = "M"
        guard let output = qrFilter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = qrContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    @MainActor
    private func generateCode() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            pairingCode = try await pairingService.createPairingNonce(
                householdId: householdId,
                managerMembershipId: managerMembershipId,
                targetProfileId: profile.id
            )
        } catch {
            pairingCode = nil
            errorMessage = error.localizedDescription
        }
    }
}
