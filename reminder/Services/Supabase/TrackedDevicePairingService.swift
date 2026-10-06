import Foundation

#if canImport(Supabase)
import Supabase
#endif

protocol TrackedDevicePairingService: Sendable {
    func createPairingNonce(
        householdId: UUID,
        managerMembershipId: UUID,
        targetProfileId: UUID
    ) async throws -> String

    func claimPairingNonce(_ code: String) async throws -> UUID
}

struct SupabaseTrackedDevicePairingService: TrackedDevicePairingService {
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding = SupabaseProvider()) {
        self.provider = provider
    }

    func createPairingNonce(
        householdId: UUID,
        managerMembershipId: UUID,
        targetProfileId: UUID
    ) async throws -> String {
        #if canImport(Supabase)
        do {
            let response = try await provider.client
                .rpc(
                    "create_tracked_device_pairing_nonce",
                    params: CreateTrackedDevicePairingNonceParams(
                        pHouseholdId: householdId,
                        pManagerMembershipId: managerMembershipId,
                        pTargetProfileId: targetProfileId
                    )
                )
                .execute()
            if let text = String(data: response.data, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                .trimmingCharacters(in: .whitespacesAndNewlines),
               text.isEmpty == false {
                return text.uppercased()
            }
            throw TrackedDevicePairingError.backendMigrationRequired
        } catch let error as TrackedDevicePairingError {
            throw error
        } catch {
            throw TrackedDevicePairingSupport.mapClaimError(error)
        }
        #else
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }

    func claimPairingNonce(_ code: String) async throws -> UUID {
        #if canImport(Supabase)
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 6 else {
            throw TrackedDevicePairingError.invalidCode
        }
        let userId: UUID
        do {
            userId = try await provider.client.auth.session.user.id
        } catch {
            throw TrackedDevicePairingError.unauthenticated
        }
        do {
            let response = try await provider.client
                .rpc(
                    "claim_tracked_device_pairing_nonce",
                    params: ClaimTrackedDevicePairingNonceParams(
                        pNonce: normalized,
                        pUserId: userId
                    )
                )
                .execute()
            if let uuid = try? JSONDecoder().decode(UUID.self, from: response.data) {
                return uuid
            }
            if let raw = String(data: response.data, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let uuid = UUID(uuidString: raw) {
                return uuid
            }
            throw TrackedDevicePairingError.invalidCode
        } catch let error as TrackedDevicePairingError {
            throw error
        } catch {
            throw TrackedDevicePairingSupport.mapClaimError(error)
        }
        #else
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }
}

struct MockTrackedDevicePairingService: TrackedDevicePairingService {
    func createPairingNonce(
        householdId: UUID,
        managerMembershipId: UUID,
        targetProfileId: UUID
    ) async throws -> String {
        _ = householdId
        _ = managerMembershipId
        _ = targetProfileId
        return "TRACK1"
    }

    func claimPairingNonce(_ code: String) async throws -> UUID {
        _ = code
        return UUID()
    }
}
