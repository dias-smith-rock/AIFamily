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
    let pPin: String
    let pDeviceModel: String

    enum CodingKeys: String, CodingKey {
        case pNonce = "p_nonce"
        case pUserId = "p_user_id"
        case pPin = "p_pin"
        case pDeviceModel = "p_device_model"
    }
}

struct ClaimTrackedDevicePairingNonceLegacyParams: Encodable, Sendable {
    let pNonce: String
    let pUserId: UUID
    let pPin: String

    enum CodingKeys: String, CodingKey {
        case pNonce = "p_nonce"
        case pUserId = "p_user_id"
        case pPin = "p_pin"
    }
}

struct GetTrackedDevicePINParams: Encodable, Sendable {
    let pHouseholdId: UUID
    let pTargetProfileId: UUID

    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pTargetProfileId = "p_target_profile_id"
    }
}

struct SetTrackedDevicePINParams: Encodable, Sendable {
    let pHouseholdId: UUID
    let pTargetProfileId: UUID
    let pPin: String

    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pTargetProfileId = "p_target_profile_id"
        case pPin = "p_pin"
    }
}

struct ReportOwnTrackedDeviceModelParams: Encodable, Sendable {
    let pModel: String

    enum CodingKeys: String, CodingKey {
        case pModel = "p_model"
    }
}

struct ReportOwnTrackedDevicePINParams: Encodable, Sendable {
    let pPin: String

    enum CodingKeys: String, CodingKey {
        case pPin = "p_pin"
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
    case invalidPIN
    case backendMigrationRequired
    case sdkUnavailable
    case remoteMessage(String)

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
        case .invalidPIN:
            return AppLocalized.localizedSync(L10n.Location.trackedPinInvalid)
        case .forbidden:
            return AppLocalized.localizedSync(L10n.Family.onlyAdminCanGenerateInviteQr)
        case .backendMigrationRequired:
            return AppLocalized.localizedSync(L10n.Location.trackedPairingBackendRequired)
        case .sdkUnavailable:
            return AppLocalized.localizedSync(L10n.Location.trackedPairingBackendRequired)
        case .remoteMessage(let text):
            return text
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
        if text.contains("invalid pin") {
            return .invalidPIN
        }
        let remote = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if remote.isEmpty == false {
            return .remoteMessage(remote)
        }
        return .backendMigrationRequired
    }
}

#endif
