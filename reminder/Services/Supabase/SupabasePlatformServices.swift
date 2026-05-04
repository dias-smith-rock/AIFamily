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

    /// 通过 `invite_link_nonces.nonce` 找到归属家庭，并以 `pending` 状态写入 `household_memberships`。
    /// 真正的核销（写 `is_used / used_by`）由 Edge Function 负责，本端只负责入驻申请。
    func joinHousehold(inviteCode: String) async throws {
        #if canImport(Supabase)
        let normalizedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCode.isEmpty == false else {
            throw HouseholdRoutingError.invalidInviteCode
        }

        let session: Session
        do {
            session = try await provider.client.auth.session
        } catch {
            throw HouseholdRoutingError.unauthenticated
        }
        let userId = session.user.id

        let nonces: [InviteNonceRow] = try await provider.client
            .from("invite_link_nonces")
            .select("household_id,is_used,expires_at")
            .eq("nonce", value: normalizedCode)
            .limit(1)
            .execute()
            .value

        guard let nonce = nonces.first else {
            throw HouseholdRoutingError.invalidInviteCode
        }
        if nonce.isUsed {
            throw HouseholdRoutingError.nonceConsumed
        }
        if nonce.expiresAt < Date() {
            throw HouseholdRoutingError.nonceExpired
        }

        let householdId = nonce.householdId

        let existing: [MembershipStatusRow] = try await provider.client
            .from("household_memberships")
            .select("status")
            .eq("household_id", value: householdId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value

        if let statusRaw = existing.first?.status,
           let status = MembershipStatus(rawValue: statusRaw) {
            switch status {
            case .active:
                throw HouseholdRoutingError.alreadyActiveMember
            case .pending:
                throw HouseholdRoutingError.joinRequestPending
            case .disabled:
                break
            }
        }

        let nickname = session.user.email ?? "新成员"

        do {
            _ = try await provider.client
                .from("household_memberships")
                .insert(NewMembershipRow(
                    householdId: householdId,
                    userId: userId,
                    role: MembershipRole.member.rawValue,
                    nickname: nickname,
                    contactMethod: ContactMethod.appPush.rawValue,
                    status: MembershipStatus.pending.rawValue
                ))
                .execute()
        } catch {
            do {
                _ = try await provider.client
                    .from("household_memberships")
                    .update(MembershipPatch(status: MembershipStatus.pending.rawValue))
                    .eq("household_id", value: householdId.uuidString)
                    .eq("user_id", value: userId.uuidString)
                    .execute()
            } catch {
                throw HouseholdRoutingError.networkFailure
            }
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

private struct InviteNonceRow: Decodable {
    let householdId: UUID
    let isUsed: Bool
    let expiresAt: Date
}

private struct NewMembershipRow: Encodable {
    let householdId: UUID
    let userId: UUID
    let role: String
    let nickname: String
    let contactMethod: String
    let status: String
}

private struct MembershipPatch: Encodable {
    let status: String
}

private struct MembershipStatusRow: Decodable {
    let status: String
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

private func isMissingRenameHouseholdRPCError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("rename_household")
        && (message.contains("not found") || message.contains("does not exist") || message.contains("could not find"))
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
