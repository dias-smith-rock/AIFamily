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
    /// 注销账号前清理该用户在全部 `family_profiles` 中的头像文件；失败不抛出。
    func cleanUpCurrentUserAvatars() async
    /// 删除托管成员档案前清理其头像；失败不抛出。
    func cleanUpProfileAvatar(profileId: UUID) async
}

protocol VoiceStorageService {
    func uploadVoiceFeedback(data: Data, fileName: String) async throws -> URL
    /// 按 Storage 对象路径批量删除；失败不抛出。
    func removeVoiceFiles(atPaths paths: [String]) async
}

protocol AvatarStorageService {
    func uploadAvatarImage(data: Data, fileName: String) async throws -> URL
    /// 按 Storage 对象路径批量删除；失败不抛出。
    func removeAvatarFiles(atPaths paths: [String]) async
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
    func createHousehold(displayName: String) async throws -> UUID
    func joinHousehold(inviteCode: String) async throws
    func renameHousehold(householdId: UUID, newName: String) async throws
    func fetchMyJoinedHouseholds() async throws -> [JoinedHousehold]
    func disbandHousehold(id: UUID, expectedName: String) async throws
    /// 解散家庭前清理该家庭下全部反馈语音；失败不抛出。
    func cleanUpHouseholdFeedbackAudios(householdId: UUID) async
    func transferOwnership(householdId: UUID, newCreatorUserId: UUID) async throws
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
    case householdNameMismatch
    case disbandUnauthorized
    case transferUnauthorized
    case transferInvalidTarget
}

// MARK: - Auth

struct SupabaseAuthService: AuthService {
    private let provider: SupabaseClientProviding
    private let avatarStorageService: AvatarStorageService
    /// 必须与 `supabase/config.toml` 中 `[auth].additional_redirect_urls` 完全一致。
    private let magicLinkRedirectURL = URL(string: "aifamily://auth-callback")

    init(provider: SupabaseClientProviding, avatarStorageService: AvatarStorageService) {
        self.provider = provider
        self.avatarStorageService = avatarStorageService
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

    func cleanUpCurrentUserAvatars() async {
        #if canImport(Supabase)
        do {
            let userId = try await provider.client.auth.session.user.id
            await cleanUpUserAvatars(userId: userId)
        } catch {
            print("⚠️ 清理用户头像失败（无法读取会话）: \(error)")
        }
        #endif
    }

    func cleanUpProfileAvatar(profileId: UUID) async {
        #if canImport(Supabase)
        do {
            let rows: [ProfileAvatarRow] = try await provider.client
                .from("family_profiles")
                .select("avatar_url")
                .eq("id", value: profileId.uuidString)
                .limit(1)
                .execute()
                .value

            let paths = rows.compactMap { row in
                SupabaseStoragePathHelper.objectPath(
                    inBucket: SupabaseStorageBucket.avatars,
                    fromStoredValue: row.avatarUrl
                )
            }
            await avatarStorageService.removeAvatarFiles(atPaths: paths)
        } catch {
            print("⚠️ 清理成员档案头像失败: \(error)")
        }
        #else
        _ = profileId
        #endif
    }

    private func cleanUpUserAvatars(userId: UUID) async {
        #if canImport(Supabase)
        do {
            let rows: [ProfileAvatarRow] = try await provider.client
                .from("family_profiles")
                .select("avatar_url")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            let paths = rows.compactMap { row in
                SupabaseStoragePathHelper.objectPath(
                    inBucket: SupabaseStorageBucket.avatars,
                    fromStoredValue: row.avatarUrl
                )
            }
            guard paths.isEmpty == false else { return }
            await avatarStorageService.removeAvatarFiles(atPaths: paths)
            print("✅ 成功清理了 \(paths.count) 个用户头像文件")
        } catch {
            print("⚠️ 清理用户头像失败: \(error)")
        }
        #else
        _ = userId
        #endif
    }
}

// MARK: - Voice Storage

private enum SupabaseStorageBucket {
    static let voiceFeedbacks = SupabaseStorageBuckets.voiceFeedbacks
    static let avatars = SupabaseStorageBuckets.avatars
}

enum SupabaseStoragePathHelper {
    /// 将 DB 中存的 public URL 或相对路径解析为 Storage `remove(paths:)` 所需的对象路径。
    static func objectPath(inBucket bucket: String, fromStoredValue value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        if raw.contains("://"), let url = URL(string: raw) {
            let path = url.path
            let markers = [
                "/object/public/\(bucket)/",
                "/storage/v1/object/public/\(bucket)/"
            ]
            for marker in markers {
                if let range = path.range(of: marker) {
                    let objectPath = String(path[range.upperBound...])
                    return objectPath.removingPercentEncoding ?? objectPath
                }
            }
            return nil
        }

        return raw
    }
}

private struct ProfileAvatarRow: Decodable {
    let avatarUrl: String?
}

private struct FeedbackVoiceUrlRow: Decodable {
    let voiceUrl: String?
}

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

    func removeVoiceFiles(atPaths paths: [String]) async {
        #if canImport(Supabase)
        let uniquePaths = Array(Set(paths.filter { $0.isEmpty == false }))
        guard uniquePaths.isEmpty == false else { return }
        do {
            _ = try await provider.client.storage
                .from(bucket)
                .remove(paths: uniquePaths)
            print("✅ 成功清理了 \(uniquePaths.count) 条反馈语音文件")
        } catch {
            print("⚠️ 清理反馈语音文件失败（可忽略）: \(error)")
        }
        #else
        _ = paths
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

    func removeAvatarFiles(atPaths paths: [String]) async {
        #if canImport(Supabase)
        let uniquePaths = Array(Set(paths.filter { $0.isEmpty == false }))
        guard uniquePaths.isEmpty == false else { return }
        do {
            _ = try await provider.client.storage
                .from(bucket)
                .remove(paths: uniquePaths)
            print("✅ 成功清理了 \(uniquePaths.count) 个头像文件")
        } catch {
            print("⚠️ 清理头像文件失败（可忽略）: \(error)")
        }
        #else
        _ = paths
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
    private let voiceStorageService: VoiceStorageService

    init(provider: SupabaseClientProviding, voiceStorageService: VoiceStorageService) {
        self.provider = provider
        self.voiceStorageService = voiceStorageService
    }

    func createHousehold(displayName: String) async throws -> UUID {
        #if canImport(Supabase)
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            throw HouseholdRoutingError.invalidHouseholdName
        }

        /// 仅校验非空后直接写入；允许同名家庭，不做前端或客户端去重查询。
        return try await createHouseholdOnBackend(normalizedName: normalizedName)
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

    func fetchMyJoinedHouseholds() async throws -> [JoinedHousehold] {
        #if canImport(Supabase)
        let session = try await provider.client.auth.session
        let userId = session.user.id
        let rawResponse = try await provider.client
            .from("household_memberships")
            .select("id, household_id, role, households(id, name, status)")
            .eq("user_id", value: userId.uuidString)
            .eq("status", value: MembershipStatus.active.rawValue)
            .order("created_at", ascending: false)
            .execute()
        #if DEBUG
        if let rawJSON = String(data: rawResponse.data, encoding: .utf8) {
            print("🔎 [OrgHub] fetchMyJoinedHouseholds raw JSON:\n\(rawJSON)")
        }
        #endif
        return try SupabaseCodec.makeDecoder().decode([JoinedHousehold].self, from: rawResponse.data)
        #else
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func cleanUpHouseholdFeedbackAudios(householdId: UUID) async {
        #if canImport(Supabase)
        do {
            let records: [FeedbackVoiceUrlRow] = try await provider.client
                .from("feedbacks")
                .select("voice_url")
                .eq("household_id", value: householdId.uuidString)
                .execute()
                .value

            let paths = records.compactMap { row in
                SupabaseStoragePathHelper.objectPath(
                    inBucket: SupabaseStorageBucket.voiceFeedbacks,
                    fromStoredValue: row.voiceUrl
                )
            }

            await voiceStorageService.removeVoiceFiles(atPaths: paths)
        } catch {
            print("⚠️ 清理家庭语音记录失败（可忽略，不阻断后续解散流程）: \(error)")
        }
        #else
        _ = householdId
        #endif
    }

    func disbandHousehold(id: UUID, expectedName: String) async throws {
        #if canImport(Supabase)
        let trimmedExpectedName = expectedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedExpectedName.isEmpty == false else {
            throw HouseholdRoutingError.householdNameMismatch
        }

        let params = DisbandHouseholdParams(
            pHouseholdId: id,
            pExpectedName: trimmedExpectedName
        )
        #if DEBUG
        print("🔎 [DisbandDebug] 开始发起解散请求: householdId=\(id.uuidString), expectedName='\(trimmedExpectedName)'")
        #endif

        do {
            _ = try await provider.client
                .rpc("disband_household", params: params)
                .execute()
            #if DEBUG
            print("✅ [DisbandDebug] RPC 执行成功！")
            #endif
        } catch {
            #if DEBUG
            print("❌ [DisbandDebug] RPC 执行失败，开始解析错误...")
            print("❌ [DisbandDebug] 常规描述: \(error.localizedDescription)")
            if let ns = error as NSError? {
                print("❌ [DisbandDebug] NSError domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            }
            print("❌ [DisbandDebug] Dump 完整对象详情:")
            dump(error)
            #endif
            throw mapDisbandHouseholdError(error)
        }
        #else
        _ = id
        _ = expectedName
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func transferOwnership(householdId: UUID, newCreatorUserId: UUID) async throws {
        #if canImport(Supabase)
        let params = TransferHouseholdOwnershipParams(
            pHouseholdId: householdId,
            pNewCreatorUserId: newCreatorUserId
        )
        do {
            _ = try await provider.client
                .rpc("transfer_household_ownership", params: params)
                .execute()
        } catch {
            throw mapTransferOwnershipError(error)
        }
        #else
        _ = householdId
        _ = newCreatorUserId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

#if canImport(Supabase)
// MARK: - Household routing (RPC + client-ordered fallback)

extension SupabaseHouseholdRoutingService {
    fileprivate func createHouseholdOnBackend(normalizedName: String) async throws -> UUID {
        let client = provider.client
        do {
            _ = try await client.auth.session
        } catch {
            throw HouseholdRoutingError.unauthenticated
        }

        do {
            return try await createHouseholdViaRPC(client: client, normalizedName: normalizedName)
        } catch {
            if isMissingCreateHouseholdRPCError(error) {
                #if DEBUG
                print("[HouseholdCreate] RPC 不可用，回退客户端顺序写入")
                #endif
                return try await createHouseholdViaClientOrderedInserts(
                    client: client,
                    normalizedName: normalizedName
                )
            }
            throw mapCreateHouseholdFlowError(error)
        }
    }

    fileprivate func createHouseholdViaRPC(client: SupabaseClient, normalizedName: String) async throws -> UUID {
        let params = CreateHouseholdWithCreatorParams(pName: normalizedName)
        Self.debugLogHouseholdInsertPayload(params, label: "rpc create_household_with_membership")

        let response = try await client
            .rpc("create_household_with_membership", params: params)
            .execute()

        #if DEBUG
        let rawBody = String(data: response.data, encoding: .utf8) ?? "<non-utf8 body>"
        print("[HouseholdCreate] rpc response status=\(response.status) raw=\(rawBody)")
        #endif

        guard (200 ... 299).contains(response.status) else {
            throw HouseholdRoutingError.backendMigrationRequired
        }

        if let householdId = Self.parseCreatedHouseholdId(from: response.data) {
            return householdId
        }

        if let latestHouseholdId = try await fetchLatestActiveHouseholdId(client: client) {
            #if DEBUG
            print("[HouseholdCreate] rpc body 未解析出 id，回退使用最新 membership 对应 household=\(latestHouseholdId.uuidString)")
            #endif
            return latestHouseholdId
        }

        throw HouseholdRoutingError.unknown
    }

    fileprivate func fetchLatestActiveHouseholdId(client: SupabaseClient) async throws -> UUID? {
        let session = try await client.auth.session
        let rows: [LatestMembershipHouseholdRow] = try await client
            .from("household_memberships")
            .select("household_id")
            .eq("user_id", value: session.user.id.uuidString)
            .eq("status", value: "active")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first?.householdId
    }

    /// 仅在 RPC 未部署时使用；`households` / `family_profiles` 禁止 `.select()`（见文件头注释）。
    fileprivate func createHouseholdViaClientOrderedInserts(
        client: SupabaseClient,
        normalizedName: String
    ) async throws -> UUID {
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

            return householdId
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

    fileprivate static func parseCreatedHouseholdId(from data: Data) -> UUID? {
        guard data.isEmpty == false else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let rows = json as? [[String: Any]] {
            for row in rows {
                for key in ["household_id", "v_household_id", "id"] {
                    if let raw = row[key] as? String, let uuid = UUID(uuidString: raw) {
                        return uuid
                    }
                }
            }
        }

        if let idString = json as? String, let uuid = UUID(uuidString: idString) {
            return uuid
        }

        return nil
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

private struct LatestMembershipHouseholdRow: Decodable {
    let householdId: UUID
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
    if message.contains("invalid_household_name") {
        return HouseholdRoutingError.invalidHouseholdName
    }
    return error
}

private func isMissingCreateHouseholdRPCError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("create_household_with_membership")
        && (message.contains("function") || message.contains("does not exist") || message.contains("42883"))
}
#endif

// MARK: - Wire payloads

private struct JoinHouseholdByNonceParams: Encodable {
    let pNonce: String
    let pUserId: UUID
}

private struct DisbandHouseholdParams: Encodable {
    let pHouseholdId: UUID
    let pExpectedName: String

    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pExpectedName = "p_expected_name"
    }
}

private struct TransferHouseholdOwnershipParams: Encodable {
    let pHouseholdId: UUID
    let pNewCreatorUserId: UUID

    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pNewCreatorUserId = "p_new_creator_user_id"
    }
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

private func isMissingDisbandHouseholdRPCError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("disband_household")
        && (message.contains("not found") || message.contains("does not exist") || message.contains("could not find"))
}

private func mapDisbandHouseholdError(_ error: Error) -> Error {
    let message = error.localizedDescription.lowercased()
    if isUnauthenticatedError(error) || message.contains("unauthenticated") {
        return HouseholdRoutingError.unauthenticated
    }
    if message.contains("household_name_mismatch") {
        return HouseholdRoutingError.householdNameMismatch
    }
    if message.contains("unauthorized") || isForbiddenError(error) {
        return HouseholdRoutingError.disbandUnauthorized
    }
    if isHouseholdNotFoundError(error) {
        return HouseholdRoutingError.householdNotFound
    }
    if isMissingDisbandHouseholdRPCError(error) {
        return HouseholdRoutingError.backendMigrationRequired
    }
    return error
}

private func mapTransferOwnershipError(_ error: Error) -> Error {
    let message = error.localizedDescription.lowercased()
    if isUnauthenticatedError(error) || message.contains("unauthenticated") {
        return HouseholdRoutingError.unauthenticated
    }
    if message.contains("unauthorized_not_creator")
        || message.contains("transfer_unauthorized")
        || (message.contains("unauthorized") && message.contains("transfer")) {
        return HouseholdRoutingError.transferUnauthorized
    }
    if message.contains("invalid_transfer_target")
        || message.contains("target_not_active")
        || message.contains("target_not_found") {
        return HouseholdRoutingError.transferInvalidTarget
    }
    if isForbiddenError(error) {
        return HouseholdRoutingError.transferUnauthorized
    }
    if isHouseholdNotFoundError(error) {
        return HouseholdRoutingError.householdNotFound
    }
    if message.contains("transfer_household_ownership")
        && (message.contains("not found") || message.contains("does not exist")) {
        return HouseholdRoutingError.backendMigrationRequired
    }
    return error
}
