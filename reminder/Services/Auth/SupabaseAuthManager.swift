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
        try await resumeOrSignInAsGuest(appRouter: appRouter).userId
    }

    /// 若 Keychain 中已有匿名会话则恢复，否则尝试归档恢复，否则创建新匿名用户。
    static func resumeOrSignInAsGuest(appRouter: AppRouter) async throws -> (userId: UUID, resumed: Bool) {
        #if canImport(Supabase)
        if let session = try? await client.auth.session, session.user.isAnonymous {
            return resumeExistingAnonymousSession(session, appRouter: appRouter)
        }

        if let restored = try await restoreArchivedAnonymousSession(appRouter: appRouter) {
            return restored
        }

        let userId = try await createNewAnonymousSession(appRouter: appRouter)
        return (userId, false)
        #else
        _ = appRouter
        throw SupabaseAuthManagerError.sdkUnavailable
        #endif
    }

    /// 登录页 OAuth 前归档当前 anonymous session，避免切换正式账号后丢失游客 UUID。
    static func archiveAnonymousSessionBeforeOAuthSignIn(appRouter: AppRouter) async {
        #if canImport(Supabase)
        guard let session = try? await client.auth.session,
              session.user.isAnonymous,
              session.refreshToken.isEmpty == false
        else {
            appRouter.clearHouseholdRoutingForIdentitySwitch()
            return
        }

        GuestSessionArchive.save(
            GuestSessionArchive.Payload(
                userId: session.user.id,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
        )
        appRouter.clearHouseholdRoutingForIdentitySwitch()
        do {
            try await client.auth.signOut(scope: .local)
            #if DEBUG
            print("[SupabaseAuthManager] signed out anonymous session locally before OAuth")
            #endif
        } catch {
            #if DEBUG
            print("[SupabaseAuthManager] local signOut before OAuth failed: \(error)")
            #endif
        }
        #if DEBUG
        print(
            "[SupabaseAuthManager] archived anonymous session userId=\(session.user.id.uuidString.lowercased())"
        )
        #endif
        #else
        _ = appRouter
        #endif
    }

    /// 返回登录页但保留 Keychain 中的 Supabase 匿名会话（同设备可恢复群组）。
    static func softExitToLogin(appRouter: AppRouter) {
        UserDefaults.standard.set(false, forKey: "isUserLoggedIn")
        appRouter.prepareForSoftExitToLogin()
        #if DEBUG
        print("[SupabaseAuthManager] softExitToLogin session preserved")
        #endif
    }

    /// 销毁 Supabase 会话并清理本地缓存。
    /// - Parameter clearGuestArchive: 仅游客「重新开始」时为 true；正式账号退出应保留归档以便恢复游客。
    static func hardSignOut(appRouter: AppRouter, clearGuestArchive: Bool = false) async throws {
        #if canImport(Supabase)
        AuthSessionGuard.shared.beginLoggingOut()
        appRouter.logVIPAccessState(trigger: "用户退出前")
        defer { Task { await AuthSessionGuard.shared.endLoggingOut() } }
        try await client.auth.signOut()
        if clearGuestArchive {
            GuestSessionArchive.clear()
        }
        UserDefaults.standard.set(false, forKey: "isUserLoggedIn")
        UserDefaults.standard.removeObject(forKey: AppRouter.offlineHouseholdSnapshotKey)
        LocalCacheManager.shared.removeAll()
        await appRouter.refreshStateFromBackend()
        #if DEBUG
        print("[SupabaseAuthManager] hardSignOut complete")
        #endif
        #else
        _ = appRouter
        throw SupabaseAuthManagerError.sdkUnavailable
        #endif
    }

    private static func createNewAnonymousSession(appRouter: AppRouter) async throws -> UUID {
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
        print("[SupabaseAuthManager] createNewAnonymousSession ok userId=\(userId.uuidString.lowercased())")
        #endif
        return userId
        #else
        _ = appRouter
        throw SupabaseAuthManagerError.sdkUnavailable
        #endif
    }

    #if canImport(Supabase)
    private static func resumeExistingAnonymousSession(
        _ session: Session,
        appRouter: AppRouter
    ) -> (userId: UUID, resumed: Bool) {
        let userId = session.user.id
        AuthSessionHints.markEverAuthenticated()
        notifyAuthUserChanged(userId: userId, isAnonymous: true)
        Task {
            await prepareRevenueCat(for: userId, appRouter: appRouter)
        }
        #if DEBUG
        print("[SupabaseAuthManager] resumeOrSignInAsGuest resumed userId=\(userId.uuidString.lowercased())")
        #endif
        return (userId, true)
    }

    private static func restoreArchivedAnonymousSession(
        appRouter: AppRouter
    ) async throws -> (userId: UUID, resumed: Bool)? {
        guard let archived = GuestSessionArchive.load() else { return nil }

        do {
            let session = try await client.auth.setSession(
                accessToken: archived.accessToken,
                refreshToken: archived.refreshToken
            )
            guard session.user.isAnonymous, session.user.id == archived.userId else {
                GuestSessionArchive.clear()
                return nil
            }
            #if DEBUG
            print(
                "[SupabaseAuthManager] restoreArchivedAnonymousSession userId=\(session.user.id.uuidString.lowercased())"
            )
            #endif
            return resumeExistingAnonymousSession(session, appRouter: appRouter)
        } catch {
            GuestSessionArchive.clear()
            #if DEBUG
            print("[SupabaseAuthManager] restoreArchivedAnonymousSession failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
    #endif

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
        let queryParams = [
            (name: "prompt", value: "select_account"),
            (name: "access_type", value: "offline"),
        ]
        #if canImport(AuthenticationServices) && canImport(UIKit)
        let oauthResponse = try await client.auth.getLinkIdentityURL(
            provider: .google,
            redirectTo: OAuthSignInSupport.oauthRedirectURL,
            queryParams: queryParams
        )
        let callbackURL = try await OAuthSignInSupport.presentInAppOAuth(url: oauthResponse.url)
        let session = try await client.auth.session(from: callbackURL)
        #else
        try await client.auth.linkIdentity(
            provider: .google,
            redirectTo: OAuthSignInSupport.oauthRedirectURL,
            queryParams: queryParams
        )
        let session = try await client.auth.session
        #endif
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
