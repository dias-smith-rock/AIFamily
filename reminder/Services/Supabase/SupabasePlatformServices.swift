import Foundation

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Protocols

protocol AuthService {
    func signInWithApple(idToken: String, nonce: String) async throws
    func sendMagicLink(email: String) async throws
    func sendPhoneOTP(phoneNumber: String) async throws
    func signOut() async throws
    func hasValidSession() async -> Bool
}

protocol VoiceStorageService {
    func uploadVoiceFeedback(data: Data, fileName: String) async throws -> URL
}

protocol FeedbackRealtimeService {
    func subscribeToFeedbackInserts(onEvent: @escaping @Sendable (Feedback) -> Void) async throws
    func unsubscribe() async
}

protocol InviteLinkService {
    func generateSignedInviteLink(
        token: String,
        contactMethod: ContactMethod,
        expiresInSeconds: Int
    ) async throws -> URL
}

protocol HouseholdRoutingService {
    func createHousehold(displayName: String) async throws
    func joinHousehold(inviteCode: String) async throws
    func renameHousehold(householdId: UUID, newName: String) async throws
}

enum HouseholdRoutingError: LocalizedError {
    case invalidHouseholdName
    case householdNameTaken
    case invalidInviteCode
    case unauthenticated
    case forbidden
    case householdNotFound
    case backendMigrationRequired
    case alreadyActiveMember
    case joinRequestPending
    case nonceExpired
    case nonceConsumed
    case networkFailure
    case unknown
}

// MARK: - Auth

struct SupabaseAuthService: AuthService {
    private let provider: SupabaseClientProviding
    /// 必须与 `supabase/config.toml` 中 `[auth].additional_redirect_urls` 完全一致。
    private let magicLinkRedirectURL = URL(string: "aifamily://login-callback")

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        #if canImport(Supabase)
        _ = try await provider.client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
        #else
        _ = idToken
        _ = nonce
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func sendMagicLink(email: String) async throws {
        #if canImport(Supabase)
        try await provider.client.auth.signInWithOTP(
            email: email,
            redirectTo: magicLinkRedirectURL
        )
        #else
        _ = email
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func sendPhoneOTP(phoneNumber: String) async throws {
        #if canImport(Supabase)
        try await provider.client.auth.signInWithOTP(phone: phoneNumber)
        #else
        _ = phoneNumber
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func signOut() async throws {
        #if canImport(Supabase)
        try await provider.client.auth.signOut()
        #else
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func hasValidSession() async -> Bool {
        #if canImport(Supabase)
        do {
            _ = try await provider.client.auth.session
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}

// MARK: - Voice Storage

struct SupabaseVoiceStorageService: VoiceStorageService {
    private let provider: SupabaseClientProviding
    private let bucket = "voice-feedbacks"

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func uploadVoiceFeedback(data: Data, fileName: String) async throws -> URL {
        #if canImport(Supabase)
        let path = "feedbacks/\(fileName)"
        _ = try await provider.client.storage
            .from(bucket)
            .upload(
                path,
                data: data,
                options: .init(
                    contentType: "audio/m4a",
                    upsert: true
                )
            )

        return try provider.client.storage
            .from(bucket)
            .getPublicURL(path: path)
        #else
        _ = data
        _ = fileName
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

// MARK: - Realtime

final class SupabaseFeedbackRealtimeService: FeedbackRealtimeService {
    #if canImport(Supabase)
    private let provider: SupabaseClientProviding
    private var channel: RealtimeChannelV2?

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func subscribeToFeedbackInserts(onEvent: @escaping @Sendable (Feedback) -> Void) async throws {
        _ = onEvent
        let channel = provider.client.realtimeV2.channel("public:feedbacks")
        self.channel = channel
        _ = try await channel.subscribeWithError()
    }

    func unsubscribe() async {
        guard let channel else { return }
        await channel.unsubscribe()
        self.channel = nil
    }
    #else
    init(provider: SupabaseClientProviding) {
        _ = provider
    }

    func subscribeToFeedbackInserts(onEvent: @escaping @Sendable (Feedback) -> Void) async throws {
        _ = onEvent
        throw SupabaseServiceError.sdkUnavailable
    }

    func unsubscribe() async {}
    #endif
}

// MARK: - Invite Link

struct SupabaseInviteLinkService: InviteLinkService {
    func generateSignedInviteLink(
        token: String,
        contactMethod: ContactMethod,
        expiresInSeconds: Int
    ) async throws -> URL {
        let functionURL = SupabaseManager.projectBaseURL
            .appendingPathComponent("functions/v1/generate-invite-link")

        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseManager.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseManager.publishableKey)", forHTTPHeaderField: "Authorization")

        let payload = InviteLinkPayload(
            token: token,
            channel: contactMethod.rawValue,
            expiresInSeconds: expiresInSeconds
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.unsupportedOperation
        }

        let decoded = try JSONDecoder().decode(InviteLinkResponse.self, from: data)
        guard let url = URL(string: decoded.url) else {
            throw SupabaseServiceError.invalidResponse
        }
        return url
    }
}

// MARK: - Household Routing

struct SupabaseHouseholdRoutingService: HouseholdRoutingService {
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func createHousehold(displayName: String) async throws {
        #if canImport(Supabase)
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            throw HouseholdRoutingError.invalidHouseholdName
        }

        do {
            let rows: [CreatedHouseholdByRPCRow] = try await provider.client
                .rpc("create_household_with_creator", params: ["p_name": normalizedName])
                .execute()
                .value
            guard rows.first != nil else {
                throw SupabaseServiceError.invalidResponse
            }
        } catch {
            if isUnauthenticatedError(error) {
                throw HouseholdRoutingError.unauthenticated
            }
            if isHouseholdNameTakenError(error) {
                throw HouseholdRoutingError.householdNameTaken
            }
            if isMissingCreateHouseholdRPCError(error) {
                throw HouseholdRoutingError.backendMigrationRequired
            }
            throw error
        }
        #else
        _ = displayName
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    /// 通过 RPC `join_household_by_nonce` 完成邀请码核销 + 加入家庭原子流程。
    func joinHousehold(inviteCode: String) async throws {
        #if canImport(Supabase)
        let normalizedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCode.isEmpty == false else {
            throw HouseholdRoutingError.invalidInviteCode
        }

        let currentUserId: UUID
        do {
            currentUserId = try await provider.client.auth.session.user.id
        } catch {
            throw HouseholdRoutingError.unauthenticated
        }

        do {
            _ = try await provider.client
                .rpc(
                    "join_household_by_nonce",
                    params: JoinHouseholdByNonceParams(
                        pNonce: normalizedCode,
                        pUserId: currentUserId
                    )
                )
                .execute()
        } catch {
            if isUnauthenticatedError(error) {
                throw HouseholdRoutingError.unauthenticated
            }
            if isInvalidOrUsedInviteCodeError(error) {
                throw HouseholdRoutingError.invalidInviteCode
            }
            if isAlreadyActiveMemberError(error) {
                throw HouseholdRoutingError.alreadyActiveMember
            }
            if isMissingJoinHouseholdRPCError(error) {
                throw HouseholdRoutingError.backendMigrationRequired
            }
            throw HouseholdRoutingError.networkFailure
        }
        #else
        _ = inviteCode
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func renameHousehold(householdId: UUID, newName: String) async throws {
        #if canImport(Supabase)
        let normalizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            throw HouseholdRoutingError.invalidHouseholdName
        }

        do {
            _ = try await provider.client
                .rpc(
                    "rename_household",
                    params: [
                        "p_household_id": householdId.uuidString,
                        "p_name": normalizedName
                    ]
                )
                .execute()
        } catch {
            if isUnauthenticatedError(error) {
                throw HouseholdRoutingError.unauthenticated
            }
            if isHouseholdNameTakenError(error) {
                throw HouseholdRoutingError.householdNameTaken
            }
            if isForbiddenError(error) {
                throw HouseholdRoutingError.forbidden
            }
            if isHouseholdNotFoundError(error) {
                throw HouseholdRoutingError.householdNotFound
            }
            if isMissingRenameHouseholdRPCError(error) {
                throw HouseholdRoutingError.backendMigrationRequired
            }
            throw error
        }
        #else
        _ = householdId
        _ = newName
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

// MARK: - Wire payloads

private struct CreatedHouseholdByRPCRow: Decodable {
    let householdId: UUID
}

private struct JoinHouseholdByNonceParams: Encodable {
    let pNonce: String
    let pUserId: UUID
}

private struct InviteLinkPayload: Encodable {
    let token: String
    let channel: String
    let expiresInSeconds: Int
}

private struct InviteLinkResponse: Decodable {
    let url: String
}

private func isUnauthenticatedError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("unauthenticated") || message.contains("jwt")
}

private func isMissingCreateHouseholdRPCError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("create_household_with_creator")
        && (message.contains("not found") || message.contains("does not exist") || message.contains("could not find"))
}

private func isMissingJoinHouseholdRPCError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("join_household_by_nonce")
        && (message.contains("not found") || message.contains("does not exist") || message.contains("could not find"))
}

private func isMissingRenameHouseholdRPCError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("rename_household")
        && (message.contains("not found") || message.contains("does not exist") || message.contains("could not find"))
}

private func isInvalidOrUsedInviteCodeError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("invalid_or_used_invitation_code")
        || message.contains("invalid or used invitation code")
        || message.contains("invalid invite code")
}

private func isAlreadyActiveMemberError(_ error: Error) -> Bool {
    error.localizedDescription.lowercased().contains("already_active_member")
}

private func isHouseholdNameTakenError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("household_name_taken")
        || (message.contains("duplicate key") && message.contains("households_name_unique_normalized_idx"))
}

private func isForbiddenError(_ error: Error) -> Bool {
    error.localizedDescription.lowercased().contains("forbidden")
}

private func isHouseholdNotFoundError(_ error: Error) -> Bool {
    error.localizedDescription.lowercased().contains("household_not_found")
}
