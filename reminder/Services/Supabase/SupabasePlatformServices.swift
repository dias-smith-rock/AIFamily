import Foundation

#if canImport(Supabase)
import Supabase
#endif

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
        channel: FamilyMember.NotificationChannel,
        expiresInSeconds: Int
    ) async throws -> URL
}

protocol HouseholdRoutingService {
    func createHousehold(displayName: String) async throws
    func joinHousehold(inviteCode: String) async throws
}

enum HouseholdRoutingError: LocalizedError {
    case invalidHouseholdName
    case invalidInviteCode
    case unauthenticated
    case alreadyActiveMember
    case joinRequestPending
    case networkFailure
    case unknown
}

struct SupabaseAuthService: AuthService {
    private let provider: SupabaseClientProviding
    private let magicLinkRedirectURL = URL(string: "aifamily://auth-callback")

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

struct SupabaseInviteLinkService: InviteLinkService {
    func generateSignedInviteLink(
        token: String,
        channel: FamilyMember.NotificationChannel,
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
            channel: channel.rawValue,
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

        let session: Session
        do {
            session = try await provider.client.auth.session
        } catch {
            throw HouseholdRoutingError.unauthenticated
        }
        let userId = session.user.id

        let households: [CreatedHouseholdRow] = try await provider.client
            .from("households")
            .insert(NewHouseholdRow(name: normalizedName))
            .select("id")
            .limit(1)
            .execute()
            .value

        guard let householdId = households.first?.id else {
            throw SupabaseServiceError.invalidResponse
        }

        _ = try await provider.client
            .from("household_memberships")
            .insert(NewMembershipRow(
                householdId: householdId,
                userId: userId,
                userRole: "owner",
                status: "active"
            ))
            .execute()
        
        #else
        _ = displayName
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func joinHousehold(inviteCode: String) async throws {
        #if canImport(Supabase)
        let normalizedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCode.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil else {
            throw HouseholdRoutingError.invalidInviteCode
        }

        let session: Session
        do {
            session = try await provider.client.auth.session
        } catch {
            throw HouseholdRoutingError.unauthenticated
        }
        let userId = session.user.id

        let members: [InviteMemberRow] = try await provider.client
            .from("family_members")
            .select("household_id")
            .eq("invite_token", value: normalizedCode)
            .limit(1)
            .execute()
            .value

        guard let householdId = members.first?.householdId else {
            throw HouseholdRoutingError.invalidInviteCode
        }

        let existingMemberships: [MembershipStatusRow] = try await provider.client
            .from("household_memberships")
            .select("status")
            .eq("household_id", value: householdId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value

        if let status = existingMemberships.first?.status.lowercased() {
            if status == "active" {
                throw HouseholdRoutingError.alreadyActiveMember
            }
            if status == "invited" || status == "pending" {
                throw HouseholdRoutingError.joinRequestPending
            }
        }

        do {
            _ = try await provider.client
                .from("household_memberships")
                .insert(NewMembershipRow(
                    householdId: householdId,
                    userId: userId,
                    userRole: "viewer",
                    status: "invited"
                ))
                .execute()
        } catch {
            do {
                _ = try await provider.client
                    .from("household_memberships")
                    .update(MembershipPatch(status: "invited"))
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
}

private struct NewHouseholdRow: Encodable {
    let name: String
}

private struct CreatedHouseholdRow: Decodable {
    let id: UUID
}

private struct InviteMemberRow: Decodable {
    let householdId: UUID

    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
    }
}

private struct NewMembershipRow: Encodable {
    let householdId: UUID
    let userId: UUID
    let userRole: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case userId = "user_id"
        case userRole = "user_role"
        case status
    }
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
