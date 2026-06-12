import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

#if canImport(Supabase)
import Supabase
#endif

struct InviteMemberView: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter

    let currentHouseholdId: UUID?
    let creatorMembershipId: UUID?
    let activeMemberCount: Int
    let hasPremiumAccess: Bool

    @State private var inviteCode: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let qrContext = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text(AppLocalized.string(L10n.Family.inviteMembersToJoin, locale: locale))
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(L10n.Family.askTheOtherPartyToUseTheWesyncAppToSca.localized)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Spacer()

                if isLoading {
                    ProgressView(AppLocalized.string(L10n.Family.generatingExclusiveInvitationCode, locale: locale))
                        .font(.system(size: 15, weight: .medium))
                } else if let inviteCode {
                    VStack(spacing: 16) {
                        qrCodeCard(from: "wefamily://join?code=\(inviteCode)")
                        Text(formattedInviteCode(inviteCode))
                            .font(.system(.largeTitle, design: .monospaced).bold())
                            .tracking(1.2)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(errorMessage ?? AppLocalized.string(L10n.Family.inviteCodeGenerationFailed, locale: locale))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                if let inviteCode {
                    ShareLink(
                        item: inviteShareText(for: inviteCode)
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                            Text(AppLocalized.string(L10n.Family.shareInvitationLink, locale: locale))
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized.string(L10n.Common.finish, locale: locale)) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await generateInviteCode()
        }
    }

    private func formattedInviteCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let first = code.prefix(3)
        let second = code.suffix(3)
        return "\(first) \(second)"
    }

    @ViewBuilder
    private func qrCodeCard(from content: String) -> some View {
        if let uiImage = generateQRCode(from: content) {
            Image(uiImage: uiImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .padding(22)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .foregroundStyle(.primary)
                .padding(22)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        qrFilter.setValue(Data(string.utf8), forKey: "inputMessage")
        qrFilter.correctionLevel = "M"
        guard let outputImage = qrFilter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaledImage = outputImage.transformed(by: transform)
        guard let cgImage = qrContext.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func generateRandomInviteCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private func inviteShareText(for inviteCode: String) -> String {
        let format = String(
            localized: L10n.Family.youReInvitedToJoinAWesyncGroupCopyThis
        )
        return String(format: format, inviteCode)
    }

    private func resolveCreatorMembershipId() throws -> UUID {
        if let creatorMembershipId {
            return creatorMembershipId
        }
        throw NSError(
            domain: "InviteMemberView",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: AppLocalized.string(L10n.Family.currentMembershipIsInvalidPleaseReEnterTh, locale: locale)]
        )
    }

    private func generateInviteCode() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let currentHouseholdId else {
            errorMessage = AppLocalized.string(L10n.Common.noGroupIsCurrentlySelected, locale: locale)
            return
        }

        guard PremiumLimits.canAddHouseholdMember(
            currentActiveCount: activeMemberCount,
            hasPremium: hasPremiumAccess
        ) else {
            dismiss()
            appRouter.presentPremiumUpgrade()
            return
        }

        #if canImport(Supabase)
        do {
            let creatorMembershipId = try resolveCreatorMembershipId()
            let client = SupabaseManager.shared.client
            let rows: [InviteNonceRPCRow] = try await client
                .rpc(
                    "get_or_create_invite_nonce",
                    params: GetOrCreateInviteNonceParams(
                        pHouseholdId: currentHouseholdId,
                        pCreatorId: creatorMembershipId
                    )
                )
                .execute()
                .value

            guard let code = rows.first?.nonce, code.isEmpty == false else {
                throw NSError(
                    domain: "InviteMemberView",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalized.string(L10n.Family.inviteCodeGenerationFailed, locale: locale)]
                )
            }
            inviteCode = code
        } catch {
            if isMissingGetOrCreateInviteNonceRPC(error) {
                errorMessage = AppLocalized.string(L10n.Family.backendInviteRpcMissing, locale: locale)
            } else if isForbiddenError(error) {
                errorMessage = AppLocalized.string(L10n.Family.onlyAdminCanGenerateInviteQr, locale: locale)
            } else {
                errorMessage = error.localizedDescription
            }
        }
        #else
        errorMessage = AppLocalized.string(L10n.Common.supabaseSdkIsNotAvailableInThisBuild, locale: locale)
        #endif
    }

    #if canImport(Supabase)
    private struct InviteNonceRPCRow: Decodable {
        let nonce: String
    }

    private struct GetOrCreateInviteNonceParams: Encodable {
        let pHouseholdId: UUID
        let pCreatorId: UUID
    }

    private func isMissingGetOrCreateInviteNonceRPC(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("get_or_create_invite_nonce")
            && (message.contains("not found")
                || message.contains("does not exist")
                || message.contains("could not find"))
    }

    private func isForbiddenError(_ error: Error) -> Bool {
        error.localizedDescription.lowercased().contains("forbidden")
    }
    #endif
}

#Preview {
    InviteMemberView(
        currentHouseholdId: UUID(),
        creatorMembershipId: UUID(),
        activeMemberCount: 1,
        hasPremiumAccess: false
    )
    .environmentObject(AppRouter())
}
