import Foundation

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Protocols

protocol AuthService {
    /// - Parameters:
    ///   - rawNonce: 与 `ASAuthorizationAppleIDRequest` 所用哈希对应的 **原始** nonce；须原样传给 Supabase 校验。
    ///   - appleGivenName / appleFamilyName / appleEmail: 仅首次授权时 Apple 可能返回，须在回调内抓取并用于档案同步。
    func signInWithApple(
        idToken: String,
        rawNonce: String,
        appleGivenName: String?,
        appleFamilyName: String?,
        appleEmail: String?
    ) async throws
    func sendMagicLink(email: String) async throws
    func sendPhoneOTP(phoneNumber: String) async throws
    func signOut() async throws
    func hasValidSession() async -> Bool
}

protocol VoiceStorageService {
    func uploadVoiceFeedback(data: Data, fileName: String) async throws -> URL
}

protocol AvatarStorageService {
    func uploadAvatarImage(data: Data, fileName: String) async throws -> URL
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
    private let magicLinkRedirectURL = URL(string: "aifamily://auth-callback")

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func signInWithApple(
        idToken: String,
        rawNonce: String,
        appleGivenName: String?,
        appleFamilyName: String?,
        appleEmail: String?
    ) async throws {
        #if canImport(Supabase)
        let client = provider.client
        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                accessToken: nil,
                nonce: rawNonce,
                gotrueMetaSecurity: nil
            )
        )
        try await Self.syncAppleIdentityToProfilesAndMetadata(
            client: client,
            givenName: appleGivenName,
            familyName: appleFamilyName,
            email: appleEmail
        )
        #else
        _ = idToken
        _ = rawNonce
        _ = appleGivenName
        _ = appleFamilyName
        _ = appleEmail
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    #if canImport(Supabase)
    /// 将 Apple 首次返回的姓名/邮箱写入 `auth.users.user_metadata`，并在 RLS 允许时更新 `family_profiles`。
    private static func syncAppleIdentityToProfilesAndMetadata(
        client: SupabaseClient,
        givenName: String?,
        familyName: String?,
        email: String?
    ) async throws {
        let session = try await client.auth.session
        let userId = session.user.id

        let nameParts = [givenName, familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let fullName = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")
        let emailTrimmed = email.flatMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var meta: [String: AnyJSON] = [:]
        if let fullName {
            meta["full_name"] = .string(fullName)
        }
        if let emailTrimmed {
            meta["apple_signin_email"] = .string(emailTrimmed)
        }
        if meta.isEmpty == false {
            _ = try await client.auth.update(user: UserAttributes(data: meta))
        }

        guard fullName != nil || emailTrimmed != nil else { return }

        struct ProfileIdRow: Decodable {
            let id: UUID
        }

        struct AppleProfileHintsPatch: Encodable {
            let name: String?
            let email: String?
            enum CodingKeys: String, CodingKey { case name, email }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(name, forKey: .name)
                try container.encodeIfPresent(email, forKey: .email)
            }
        }

        let patch = AppleProfileHintsPatch(name: fullName, email: emailTrimmed)

        let rows: [ProfileIdRow] = try await client
            .from("family_profiles")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        for row in rows {
            try await client
                .from("family_profiles")
                .update(patch)
                .eq("id", value: row.id.uuidString)
                .execute()
        }
    }
    #endif

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

struct SupabaseAvatarStorageService: AvatarStorageService {
    private let provider: SupabaseClientProviding
    private let bucket = "avatars"

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func uploadAvatarImage(data: Data, fileName: String) async throws -> URL {
        #if canImport(Supabase)
        let path = "profiles/\(fileName)"
        _ = try await provider.client.storage
            .from(bucket)
            .upload(
                path,
                data: data,
                options: .init(
                    contentType: "image/jpeg",
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

        /// 优先走 RPC `create_household_with_creator`（服务端 `auth.uid()` 写入 creator_id，且不受 households SELECT RLS 影响）。
        /// 直连 insert 时禁止对 `households` / `family_profiles` 使用 `.select()`：首条 membership 建立前，
        /// `get_user_household_ids()` 为空，INSERT … RETURNING 会在 SELECT 策略上触发 42501。
        try await createHouseholdOnBackend(normalizedName: normalizedName)
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
            print("加入家庭详细错误: \(error)")
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
            throw error
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
            print("重命名家庭详细错误: \(error)")
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

#if canImport(Supabase)
// MARK: - Household routing (RPC + client-ordered fallback)

extension SupabaseHouseholdRoutingService {
    fileprivate func createHouseholdOnBackend(normalizedName: String) async throws {
        let client = provider.client
        do {
            _ = try await client.auth.session
        } catch {
            throw HouseholdRoutingError.unauthenticated
        }

        do {
            try await createHouseholdViaRPC(client: client, normalizedName: normalizedName)
        } catch {
            if isMissingCreateHouseholdRPCError(error) {
                #if DEBUG
                print("[HouseholdCreate] RPC 不可用，回退客户端顺序写入")
                #endif
                try await createHouseholdViaClientOrderedInserts(client: client, normalizedName: normalizedName)
                return
            }
            throw mapCreateHouseholdFlowError(error)
        }
    }

    fileprivate func createHouseholdViaRPC(client: SupabaseClient, normalizedName: String) async throws {
        let params = CreateHouseholdWithCreatorParams(pName: normalizedName)
        Self.debugLogHouseholdInsertPayload(params, label: "rpc create_household_with_creator")

        let response = try await client
            .rpc("create_household_with_creator", params: params)
            .execute()

        #if DEBUG
        let rawBody = String(data: response.data, encoding: .utf8) ?? "<non-utf8 body>"
        print("[HouseholdCreate] rpc response status=\(response.status) raw=\(rawBody)")
        #endif

        guard (200 ... 299).contains(response.status) else {
            throw HouseholdRoutingError.backendMigrationRequired
        }
    }

    /// 仅在 RPC 未部署时使用；`households` / `family_profiles` 禁止 `.select()`（见文件头注释）。
    fileprivate func createHouseholdViaClientOrderedInserts(
        client: SupabaseClient,
        normalizedName: String
    ) async throws {
        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            throw HouseholdRoutingError.unauthenticated
        }

        let currentUserId = session.user.id
        guard currentUserId.uuidString.isEmpty == false else {
            #if DEBUG
            print("[HouseholdCreate] 错误：当前没有找到登录用户")
            #endif
            throw HouseholdRoutingError.unauthenticated
        }

        let householdId = UUID()
        let profileId = UUID()
        var householdIdForRollback: UUID?

        do {
            let householdPayload = HouseholdCreatorInsertPayload(
                id: householdId,
                name: normalizedName,
                creatorId: currentUserId
            )
            Self.debugLogHouseholdInsertPayload(householdPayload)

            try await client
                .from("households")
                .insert(householdPayload)
                .execute()
            householdIdForRollback = householdId

            let nickname = Self.resolvedCreatorDisplayName(session: session)
            let profilePayload = FamilyProfileCreatorInsertPayload(
                id: profileId,
                householdId: householdId,
                name: nickname,
                userId: currentUserId
            )
            Self.debugLogHouseholdInsertPayload(profilePayload, label: "family_profiles")

            try await client
                .from("family_profiles")
                .insert(profilePayload)
                .execute()

            let membershipId = UUID()
            let now = Date()
            let membershipRow = HouseholdMembership(
                id: membershipId,
                householdId: householdId,
                userId: currentUserId,
                profileId: profileId,
                role: .creator,
                nickname: nickname,
                avatarUrl: nil,
                contactMethod: .appPush,
                phoneNumber: nil,
                email: nil,
                status: .active,
                joinedAt: now,
                createdAt: now,
                updatedAt: now
            )
            let insertedMembership: HouseholdMembership = try await client
                .from("household_memberships")
                .insert(membershipRow)
                .select()
                .single()
                .execute()
                .value

            let linkPayload = FamilyProfileMembershipLinkPayload(createdBy: insertedMembership.id)
            Self.debugLogHouseholdInsertPayload(linkPayload, label: "family_profiles.update")
            try await client
                .from("family_profiles")
                .update(linkPayload)
                .eq("id", value: profileId.uuidString)
                .execute()
        } catch {
            print("创建家庭详细错误: \(error)")
            if let hid = householdIdForRollback {
                do {
                    try await client.from("households").delete().eq("id", value: hid.uuidString).execute()
                } catch {
                    print("创建家庭回滚删除 households 失败: \(error)")
                }
            }
            throw mapCreateHouseholdFlowError(error)
        }
    }

    fileprivate static func debugLogHouseholdInsertPayload<T: Encodable>(
        _ payload: T,
        label: String = "households"
    ) {
        #if DEBUG
        do {
            let data = try SupabaseCodec.makeEncoder().encode(payload)
            let json = String(data: data, encoding: .utf8) ?? "<invalid utf8>"
            print("[HouseholdCreate] \(label) insert payload: \(json)")
        } catch {
            print("[HouseholdCreate] \(label) payload encode failed: \(error)")
        }
        #endif
    }

    fileprivate static func resolvedCreatorDisplayName(session: Session) -> String {
        let user = session.user
        if let metaValue = user.userMetadata["full_name"] {
            if case let .string(value) = metaValue {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }
        if let email = user.email, email.isEmpty == false {
            return email
        }
        return "管理员"
    }
}

private struct CreateHouseholdWithCreatorParams: Encodable {
    let pName: String

    enum CodingKeys: String, CodingKey {
        case pName = "p_name"
    }
}

private struct HouseholdCreatorInsertPayload: Encodable {
    let id: UUID
    let name: String
    let creatorId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case creatorId = "creator_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(creatorId.uuidString.lowercased(), forKey: .creatorId)
    }
}

private struct FamilyProfileCreatorInsertPayload: Encodable {
    let id: UUID
    let householdId: UUID
    let name: String
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case name
        case userId = "user_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(householdId.uuidString.lowercased(), forKey: .householdId)
        try container.encode(name, forKey: .name)
        try container.encode(userId.uuidString.lowercased(), forKey: .userId)
    }
}

private struct FamilyProfileMembershipLinkPayload: Encodable {
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case createdBy = "created_by"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(createdBy.uuidString.lowercased(), forKey: .createdBy)
    }
}

private func mapCreateHouseholdFlowError(_ error: Error) -> Error {
    let message = error.localizedDescription.lowercased()
    if isUnauthenticatedError(error) || message.contains("unauthenticated") {
        return HouseholdRoutingError.unauthenticated
    }
    if isHouseholdNameTakenError(error) || message.contains("household_name_taken") {
        return HouseholdRoutingError.householdNameTaken
    }
    if message.contains("invalid_household_name") {
        return HouseholdRoutingError.invalidHouseholdName
    }
    return error
}

private func isMissingCreateHouseholdRPCError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("create_household_with_creator")
        && (message.contains("function") || message.contains("does not exist") || message.contains("42883"))
}
#endif

// MARK: - Wire payloads

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
