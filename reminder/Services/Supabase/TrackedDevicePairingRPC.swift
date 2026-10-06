import Foundation

#if canImport(Supabase)

struct CreateTrackedDevicePairingNonceParams: Encodable, Sendable {
    let pHouseholdId: UUID
    let pManagerMembershipId: UUID
    let pTargetProfileId: UUID

    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pManagerMembershipId = "p_manager_membership_id"
        case pTargetProfileId = "p_target_profile_id"
    }
}

struct ClaimTrackedDevicePairingNonceParams: Encodable, Sendable {
    let pNonce: String
    let pUserId: UUID

    enum CodingKeys: String, CodingKey {
        case pNonce = "p_nonce"
        case pUserId = "p_user_id"
    }
}

enum TrackedDevicePairingError: LocalizedError {
    case unauthenticated
    case invalidCode
    case expired
    case alreadyUsed
    case profileBound
    case alreadyMemberDifferentProfile
    case forbidden
    case backendMigrationRequired
    case sdkUnavailable

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return AppLocalized.localizedSync(L10n.Auth.sessionAbnormalRetry)
        case .invalidCode:
            return AppLocalized.localizedSync(L10n.Location.trackedPairingInvalidCode)
        case .expired:
            return AppLocalized.localizedSync(L10n.Location.trackedPairingCodeExpired)
        case .alreadyUsed:
            return AppLocalized.localizedSync(L10n.Location.trackedPairingCodeUsed)
        case .profileBound:
            return AppLocalized.localizedSync(L10n.Location.trackedPairingProfileBound)
        case .alreadyMemberDifferentProfile:
            return AppLocalized.localizedSync(L10n.Location.trackedPairingAlreadyMember)
        case .forbidden:
            return AppLocalized.localizedSync(L10n.Family.onlyAdminCanGenerateInviteQr)
        case .backendMigrationRequired:
            return AppLocalized.localizedSync(L10n.Location.trackedPairingBackendRequired)
        case .sdkUnavailable:
            return AppLocalized.localizedSync(L10n.Location.trackedPairingBackendRequired)
        }
    }
}

enum TrackedDevicePairingSupport {
    static func mapClaimError(_ error: Error) -> TrackedDevicePairingError {
        let text = (String(describing: error) + " " + error.localizedDescription).lowercased()
        if text.contains("schema cache") || text.contains("could not find the function") {
            return .backendMigrationRequired
        }
        if text.contains("expired") {
            return .expired
        }
        if text.contains("already used") {
            return .alreadyUsed
        }
        if text.contains("already bound") || text.contains("profile already bound") {
            return .profileBound
        }
        if text.contains("different profile") {
            return .alreadyMemberDifferentProfile
        }
        if text.contains("forbidden") || text.contains("42501") {
            return .forbidden
        }
        if text.contains("not authenticated") {
            return .unauthenticated
        }
        if text.contains("invalid pairing") {
            return .invalidCode
        }
        return .invalidCode
    }
}

#endif
