import Foundation

#if canImport(Supabase)
import Supabase
#endif

extension Notification.Name {
    /// Supabase 会话用户变更（匿名登录 / 转正 / 登出）。
    static let supabaseAuthUserDidChange = Notification.Name("supabaseAuthUserDidChange")
}

/// Supabase Auth 与 RevenueCat 身份对齐（含匿名游客）。
@MainActor
enum SupabaseAuthManager {
    #if canImport(Supabase)
    private static var client: SupabaseClient { SupabaseManager.shared.client }
    #endif

    /// 匿名登录并绑定 RevenueCat `appUserID` 为 Supabase UUID。
    static func signInAsGuest(appRouter: AppRouter) async throws -> UUID {
        #if canImport(Supabase)
        let session = try await client.auth.signInAnonymously()
        let userId = session.user.id
        AuthSessionHints.markEverAuthenticated()
        notifyAuthUserChanged(userId: userId, isAnonymous: session.user.isAnonymous)
        Task {
            await ensureCurrentUserFamilyProfile()
            await prepareRevenueCat(for: userId, appRouter: appRouter)
        }
        #if DEBUG
        print("[SupabaseAuthManager] signInAsGuest ok userId=\(userId.uuidString.lowercased())")
        #endif
        return userId
        #else
        _ = appRouter
        throw SupabaseAuthManagerError.sdkUnavailable
        #endif
    }

    static func currentUserId() async -> UUID? {
        #if canImport(Supabase)
        do {
            return try await client.auth.session.user.id
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    static func isAnonymousUser() async -> Bool {
        #if canImport(Supabase)
        do {
            return try await client.auth.session.user.isAnonymous
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// App 冷启动：若已有 Supabase 会话，用 UUID 初始化 / 对齐 RevenueCat。
    static func bootstrapRevenueCatIfNeeded(appRouter: AppRouter) async {
        #if canImport(Supabase)
        guard let userId = await currentUserId() else { return }
        await prepareRevenueCat(for: userId, appRouter: appRouter)
        #else
        _ = appRouter
        #endif
    }

    #if canImport(Supabase) && canImport(AuthenticationServices)
    static func linkAppleIdentity(
        idToken: String,
        rawNonce: String,
        appRouter: AppRouter
    ) async throws {
        let session = try await client.auth.linkIdentityWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                accessToken: nil,
                nonce: rawNonce,
                gotrueMetaSecurity: nil
            )
        )
        let userId = session.user.id
        await prepareRevenueCat(for: userId, appRouter: appRouter)
        notifyAuthUserChanged(userId: userId, isAnonymous: session.user.isAnonymous)
        await SubscriptionTrigger.shared.syncSubscriptionFallback(appRouter: appRouter)
        #if DEBUG
        print("[SupabaseAuthManager] linkAppleIdentity ok userId=\(userId.uuidString.lowercased()) isAnonymous=\(session.user.isAnonymous)")
        #endif
    }
    #endif

    static func linkGoogleIdentity(appRouter: AppRouter) async throws {
        #if canImport(Supabase)
        try await client.auth.linkIdentity(
            provider: .google,
            redirectTo: OAuthSignInSupport.oauthRedirectURL,
            queryParams: [
                (name: "prompt", value: "select_account"),
                (name: "access_type", value: "offline"),
            ]
        )
        let session = try await client.auth.session
        let userId = session.user.id
        await prepareRevenueCat(for: userId, appRouter: appRouter)
        notifyAuthUserChanged(userId: userId, isAnonymous: session.user.isAnonymous)
        await SubscriptionTrigger.shared.syncSubscriptionFallback(appRouter: appRouter)
        #if DEBUG
        print("[SupabaseAuthManager] linkGoogleIdentity ok userId=\(userId.uuidString.lowercased()) isAnonymous=\(session.user.isAnonymous)")
        #endif
        #else
        _ = appRouter
        throw SupabaseAuthManagerError.sdkUnavailable
        #endif
    }

    private static func prepareRevenueCat(for userId: UUID, appRouter: AppRouter) async {
        await RevenueCatSubscriptionService.shared.prepareForUser(
            userId: userId,
            appRouter: appRouter
        )
    }

    private static func ensureCurrentUserFamilyProfile() async {
        do {
            _ = try await client.rpc("ensure_current_user_family_profile").execute()
        } catch {
            #if DEBUG
            print("[SupabaseAuthManager] ensure_current_user_family_profile failed: \(error)")
            #endif
        }
    }

    private static func notifyAuthUserChanged(userId: UUID, isAnonymous: Bool) {
        NotificationCenter.default.post(
            name: .supabaseAuthUserDidChange,
            object: nil,
            userInfo: [
                "userId": userId.uuidString.lowercased(),
                "isAnonymous": isAnonymous,
            ]
        )
    }
}

enum SupabaseAuthManagerError: LocalizedError {
    case sdkUnavailable

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return AppLocalized.localizedSync(L10n.Common.supabaseSdkIsNotAvailableInThisBuild)
        }
    }
}
