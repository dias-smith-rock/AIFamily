import Foundation

#if canImport(Supabase)
import Supabase
#endif

extension Notification.Name {
    /// Supabase 会话用户变更（匿名登录 / 转正 / 登出）。
    static let supabaseAuthUserDidChange = Notification.Name("supabaseAuthUserDidChange")
}

/// Supabase Auth 与 RevenueCat 身份对齐（含匿名游客）。
/// 游客与正式账号 session 分别持久化在独立 Keychain 槽位，切换时互不覆盖。
@MainActor
enum SupabaseAuthManager {
    #if canImport(Supabase)
    private static var client: SupabaseClient { SupabaseManager.shared.client }
    #endif

    /// 匿名登录并绑定 RevenueCat `appUserID` 为 Supabase UUID。
    static func signInAsGuest(appRouter: AppRouter) async throws -> UUID {
        try await resumeOrSignInAsGuest(appRouter: appRouter).userId
    }

    /// 游客登录成功后将当前 Supabase session 的 access / refresh token 写入游客 Keychain 槽位。
    static func saveGuestSessionToKeychain() async {
        #if canImport(Supabase)
        guard let session = try? await client.auth.session,
              session.user.isAnonymous,
              session.refreshToken.isEmpty == false
        else {
            return
        }
        persistGuestSession(session)
        #if DEBUG
        print(
            "[SupabaseAuthManager] saveGuestSessionToKeychain ok userId=\(session.user.id.uuidString.lowercased())"
        )
        #endif
        #endif
    }

    /// 进入游客模式：SDK 内 anonymous → Keychain 注入（setSession）→ 仅槽位为空时 signInAnonymously。
    static func resumeOrSignInAsGuest(appRouter: AppRouter) async throws -> (userId: UUID, resumed: Bool) {
        #if canImport(Supabase)
        if let session = try? await client.auth.session {
            if session.user.isAnonymous {
                persistGuestSession(session)
                #if DEBUG
                await GuestSessionDiagnostics.logAsync("guest.resume.branch=keychain", appRouter: appRouter)
                #endif
                return resumeExistingAnonymousSession(session, appRouter: appRouter)
            }
            persistFormalSession(session)
        }

        if GuestSessionArchive.hasSavedTokens {
            #if DEBUG
            await GuestSessionDiagnostics.logAsync("guest.resume.attemptArchive", appRouter: appRouter)
            #endif
            let restored = try await activateGuestSessionFromStore(appRouter: appRouter)
            #if DEBUG
            await GuestSessionDiagnostics.logAsync(
                "guest.resume.branch=archive",
                appRouter: appRouter,
                note: "userId=\(restored.userId.uuidString.lowercased())"
            )
            #endif
            return restored
        }

        #if DEBUG
        await GuestSessionDiagnostics.logAsync("guest.resume.branch=createNew", appRouter: appRouter)
        #endif
        let userId = try await createNewAnonymousSession(appRouter: appRouter)
        if let session = try? await client.auth.session {
            persistGuestSession(session)
        }
        return (userId, false)
        #else
        _ = appRouter
        throw SupabaseAuthManagerError.sdkUnavailable
        #endif
    }

    /// 登录页 OAuth 前：写入游客 Keychain 槽位并通过 HTTP 换票保活，再清 SDK 本地会话以便 OAuth。
    static func archiveAnonymousSessionBeforeOAuthSignIn(appRouter: AppRouter) async {
        #if canImport(Supabase)
        OAuthLoginPerformanceTracer.mark("oauth.archive.begin", appRouter: appRouter)
        if let session = try? await client.auth.session,
           session.user.isAnonymous,
           session.refreshToken.isEmpty == false
        {
            OAuthLoginPerformanceTracer.mark(
                "oauth.archive.anonymousSDKSession",
                note: "userId=\(session.user.id.uuidString.lowercased())",
                appRouter: appRouter
            )
            persistGuestSession(session)
            let refreshResult = await GuestArchiveTokenRefresher.refreshAndPersistGuestTokens(
                refreshToken: session.refreshToken,
                expectedUserId: session.user.id,
                context: "beforeOAuth.sdkSession"
            )
            OAuthLoginPerformanceTracer.mark(
                "oauth.archive.httpRefresh",
                note: "result=\(refreshResult)",
                appRouter: appRouter
            )
            #if DEBUG
            print(
                "[SupabaseAuthManager] archived anonymous before OAuth userId=\(session.user.id.uuidString.lowercased()) httpRefresh=\(refreshResult)"
            )
            #endif
            appRouter.clearHouseholdRoutingForIdentitySwitch()
            do {
                try await client.auth.signOut(scope: .local)
                OAuthLoginPerformanceTracer.mark("oauth.archive.localSignOut.ok", appRouter: appRouter)
                #if DEBUG
                print("[SupabaseAuthManager] signed out anonymous session locally before OAuth")
                #endif
            } catch {
                OAuthLoginPerformanceTracer.mark(
                    "oauth.archive.localSignOut.failed",
                    note: error.localizedDescription,
                    appRouter: appRouter
                )
                #if DEBUG
                print("[SupabaseAuthManager] local signOut before OAuth failed: \(error)")
                #endif
            }
            OAuthLoginPerformanceTracer.mark("oauth.archive.end", note: "path=anonymousSDKSession", appRouter: appRouter)
            return
        }

        if GuestSessionArchive.hasSavedTokens {
            OAuthLoginPerformanceTracer.mark(
                "oauth.archive.archiveOnly.skipped",
                note: "backgroundRefresh",
                appRouter: appRouter
            )
            Task {
                let refreshResult = await GuestArchiveTokenRefresher.refreshArchivedGuestTokens(
                    context: "beforeOAuth.archiveOnly.background"
                )
                if case .failed(_, let message) = refreshResult,
                   shouldClearStaleGuestArchive(afterRefreshMessage: message)
                {
                    GuestSessionArchive.clear()
                    #if DEBUG
                    print("[SupabaseAuthManager] cleared stale guest archive after refresh failure: \(message)")
                    #endif
                }
            }
        }

        appRouter.clearHouseholdRoutingForIdentitySwitch()
        OAuthLoginPerformanceTracer.mark("oauth.archive.end", note: "path=noActiveAnonymousSession", appRouter: appRouter)
        #else
        _ = appRouter
        #endif
    }

    #if canImport(Supabase)
    private static func shouldClearStaleGuestArchive(afterRefreshMessage message: String) -> Bool {
        let normalized = message.lowercased()
        if normalized.contains("bad_json") { return true }
        if normalized.contains("invalid") { return true }
        if normalized.contains("refresh_token") { return true }
        return false
    }
    #endif

    /// OAuth / 正式登录成功后，将当前 session 同步到正式 Keychain 槽位。
    static func persistFormalSessionIfNeeded() async {
        #if canImport(Supabase)
        guard let session = try? await client.auth.session,
              session.user.isAnonymous == false,
              session.refreshToken.isEmpty == false
        else {
            return
        }
        persistFormalSession(session)
        #if DEBUG
        print(
            "[SupabaseAuthManager] persisted formal session userId=\(session.user.id.uuidString.lowercased())"
        )
        #endif
        #endif
    }

    /// 返回登录页但保留 Keychain 中的 Supabase 匿名会话（同设备可恢复群组）。
    static func softExitToLogin(appRouter: AppRouter) {
        Task {
            await persistActiveSessionToMatchingSlot()
        }
        UserDefaults.standard.set(false, forKey: "isUserLoggedIn")
        appRouter.prepareForSoftExitToLogin()
        #if DEBUG
        print("[SupabaseAuthManager] softExitToLogin session preserved")
        #endif
    }

    /// 清除失效的游客槽位并创建全新 anonymous session（破坏性操作）。
    static func resetGuestSessionAndSignIn(appRouter: AppRouter) async throws -> (userId: UUID, resumed: Bool) {
        #if canImport(Supabase)
        GuestSessionArchive.clear()
        if let session = try? await client.auth.session, session.user.isAnonymous {
            try await client.auth.signOut()
        }
        let userId = try await createNewAnonymousSession(appRouter: appRouter)
        return (userId, false)
        #else
        _ = appRouter
        throw SupabaseAuthManagerError.sdkUnavailable
        #endif
    }

    /// 完成游客登录 bootstrap（与 `startSupabaseGuestExperience` 共用）。
    static func finishGuestSignInBootstrap(
        appRouter: AppRouter,
        userId: UUID
    ) async {
        appRouter.markOAuthBootstrapCompleted()
        appRouter.syncSessionIdentityFromPersistedSessionIfAvailable()
        _ = appRouter.restoreOfflineHouseholdContextIfNeeded()
        await appRouter.refreshStateFromBackend()
        appRouter.finishAnonymousSignIn(userId: userId)
        await saveGuestSessionToKeychain()
    }

    /// 销毁 Supabase 会话并清理本地缓存。
    /// - Parameter clearGuestArchive: 仅游客「重新开始」时为 true；正式账号退出应保留游客槽位。
    static func hardSignOut(appRouter: AppRouter, clearGuestArchive: Bool = false) async throws {
        #if canImport(Supabase)
        AuthSessionGuard.shared.beginLoggingOut()
        appRouter.logVIPAccessState(trigger: "用户退出前")
        defer { Task { await AuthSessionGuard.shared.endLoggingOut() } }

        let isOnline = await NetworkMonitor.shared.isConnected

        if let session = client.auth.currentSession {
            if session.user.isAnonymous {
                persistGuestSession(session)
            } else {
                persistFormalSession(session)
                if isOnline {
                    let refreshResult = await GuestArchiveTokenRefresher.refreshArchivedGuestTokens(
                        context: "hardSignOut.beforeFormalSignOut"
                    )
                    #if DEBUG
                    print("[SupabaseAuthManager] guest archive refresh on formal signOut result=\(refreshResult)")
                    #endif
                } else {
                    #if DEBUG
                    print("[SupabaseAuthManager] skipped guest archive refresh on formal signOut (offline)")
                    #endif
                }
            }
        }

        try await signOutFromSDK(preferGlobal: isOnline)
        if clearGuestArchive {
            GuestSessionArchive.clear()
        }
        UserDefaults.standard.set(false, forKey: "isUserLoggedIn")
        UserDefaults.standard.removeObject(forKey: AppRouter.offlineHouseholdSnapshotKey)
        if clearGuestArchive {
            LocalCacheManager.shared.removeAll()
        }
        appRouter.applyLocalStateAfterHardSignOut()
        if isOnline {
            await appRouter.refreshStateFromBackend()
        }
        #if DEBUG
        print("[SupabaseAuthManager] hardSignOut complete clearGuestArchive=\(clearGuestArchive) online=\(isOnline)")
        #endif
        #else
        _ = appRouter
        throw SupabaseAuthManagerError.sdkUnavailable
        #endif
    }

    #if canImport(Supabase)
    /// Supabase SDK 会先 `sessionManager.remove()` 再请求 `/logout`；离线时后者失败但仍应视为退出成功。
    private static func signOutFromSDK(preferGlobal: Bool) async throws {
        do {
            if preferGlobal {
                try await client.auth.signOut()
            } else {
                try await client.auth.signOut(scope: .local)
            }
        } catch {
            if client.auth.currentSession == nil {
                #if DEBUG
                print(
                    "[SupabaseAuthManager] signOut network error ignored after local session cleared: \(error.localizedDescription)"
                )
                #endif
                return
            }
            throw error
        }
    }
    #endif

    private static func createNewAnonymousSession(appRouter: AppRouter) async throws -> UUID {
        #if canImport(Supabase)
        let session = try await client.auth.signInAnonymously()
        let userId = session.user.id
        persistGuestSession(session)
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
        persistGuestSession(session)
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

    /// 从游客 Keychain 槽位激活 session：setSession 注入 → refresh 降级，失败则要求用户清除重来。
    private static func activateGuestSessionFromStore(
        appRouter: AppRouter
    ) async throws -> (userId: UUID, resumed: Bool) {
        guard let archived = GuestSessionArchive.load() else {
            throw SupabaseAuthManagerError.guestSessionNotFound
        }

        #if DEBUG
        await GuestSessionDiagnostics.logAsync(
            "guest.archive.beforeActivate",
            appRouter: appRouter,
            note: "archivedUserId=\(archived.userId.uuidString.lowercased())"
        )
        #endif

        let httpRefresh = await GuestArchiveTokenRefresher.refreshArchivedGuestTokens(
            context: "guestRestore.beforeInject"
        )
        #if DEBUG
        await GuestSessionDiagnostics.logAsync(
            "guest.archive.httpRefresh",
            appRouter: appRouter,
            note: "archivedUserId=\(archived.userId.uuidString.lowercased()) result=\(httpRefresh)"
        )
        #endif

        guard let payloadForInject = GuestSessionArchive.load() else {
            throw SupabaseAuthManagerError.guestSessionNotFound
        }

        let session: Session
        do {
            session = try await activateGuestSessionFromArchivedPayload(payloadForInject, appRouter: appRouter)
        } catch let error as SupabaseAuthManagerError {
            throw error
        } catch {
            throw SupabaseAuthManagerError.guestSessionRestoreFailedNeedsReset(
                archivedUserId: archived.userId
            )
        }

        guard session.user.isAnonymous, session.user.id == payloadForInject.userId else {
            #if DEBUG
            GuestSessionDiagnostics.log(
                "guest.archive.sessionMismatch",
                appRouter: appRouter,
                note: "expected=\(payloadForInject.userId.uuidString.lowercased()) got=\(session.user.id.uuidString.lowercased()) isAnonymous=\(session.user.isAnonymous)"
            )
            #endif
            throw SupabaseAuthManagerError.guestSessionRestoreFailedNeedsReset(
                archivedUserId: payloadForInject.userId
            )
        }

        persistGuestSession(session)
        #if DEBUG
        await GuestSessionDiagnostics.logAsync(
            "guest.archive.afterActivate",
            appRouter: appRouter,
            note: "userId=\(session.user.id.uuidString.lowercased())"
        )
        #endif
        return resumeExistingAnonymousSession(session, appRouter: appRouter)
    }

    private static func activateGuestSessionFromArchivedPayload(
        _ archived: PersistedAuthSessionKeychain.Payload,
        appRouter: AppRouter
    ) async throws -> Session {
        var lastError: Error?

        do {
            let session = try await client.auth.setSession(
                accessToken: archived.accessToken,
                refreshToken: archived.refreshToken
            )
            #if DEBUG
            await GuestSessionDiagnostics.logAsync(
                "guest.archive.activate.setSession.ok",
                appRouter: appRouter,
                note: "archivedUserId=\(archived.userId.uuidString.lowercased())"
            )
            #endif
            return session
        } catch {
            lastError = error
            #if DEBUG
            await GuestSessionDiagnostics.logAsync(
                "guest.archive.activate.setSession.failed",
                appRouter: appRouter,
                note: "archivedUserId=\(archived.userId.uuidString.lowercased()) \(authErrorDebugDescription(error))"
            )
            #endif
        }

        do {
            let session = try await client.auth.refreshSession(refreshToken: archived.refreshToken)
            #if DEBUG
            await GuestSessionDiagnostics.logAsync(
                "guest.archive.activate.refresh.ok",
                appRouter: appRouter,
                note: "archivedUserId=\(archived.userId.uuidString.lowercased())"
            )
            #endif
            return session
        } catch {
            lastError = error
            #if DEBUG
            await GuestSessionDiagnostics.logAsync(
                "guest.archive.activate.refresh.failed",
                appRouter: appRouter,
                note: "archivedUserId=\(archived.userId.uuidString.lowercased()) \(authErrorDebugDescription(error))"
            )
            #endif
        }

        #if DEBUG
        if let lastError {
            print(
                "[SupabaseAuthManager] guest archive activate exhausted archivedUserId=\(archived.userId.uuidString.lowercased()) lastError=\(authErrorDebugDescription(lastError))"
            )
        }
        #endif

        throw SupabaseAuthManagerError.guestSessionRestoreFailedNeedsReset(
            archivedUserId: archived.userId
        )
    }

    static func persistSessionToDualStore(_ session: Session) {
        if session.user.isAnonymous {
            persistGuestSession(session)
        } else {
            persistFormalSession(session)
        }
    }

    private static func authErrorDebugDescription(_ error: Error) -> String {
        #if canImport(Supabase)
        if let authError = error as? AuthError {
            return "AuthError code=\(authError.errorCode.rawValue) message=\(authError.message)"
        }
        #endif
        return error.localizedDescription
    }

    private static func persistGuestSession(_ session: Session) {
        guard session.user.isAnonymous, session.refreshToken.isEmpty == false else { return }
        GuestSessionArchive.save(
            PersistedAuthSessionKeychain.Payload(
                userId: session.user.id,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
        )
    }

    private static func persistFormalSession(_ session: Session) {
        guard session.user.isAnonymous == false, session.refreshToken.isEmpty == false else { return }
        FormalSessionArchive.save(
            PersistedAuthSessionKeychain.Payload(
                userId: session.user.id,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
        )
        AuthSessionHints.markFormalAccountUsed()
    }

    private static func persistActiveSessionToMatchingSlot() async {
        guard let session = try? await client.auth.session else { return }
        if session.user.isAnonymous {
            persistGuestSession(session)
        } else {
            persistFormalSession(session)
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
        if session.user.isAnonymous {
            persistGuestSession(session)
        } else {
            persistFormalSession(session)
        }
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
        if session.user.isAnonymous {
            persistGuestSession(session)
        } else {
            persistFormalSession(session)
        }
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
    case guestSessionNotFound
    case guestSessionRestoreFailed(String)
    case guestSessionRestoreFailedNeedsReset(archivedUserId: UUID)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return AppLocalized.localizedSync(L10n.Common.supabaseSdkIsNotAvailableInThisBuild)
        case .guestSessionNotFound:
            return AppLocalized.localizedSync(L10n.Auth.noSavedGuestSessionWasFoundOnThisDevice)
        case .guestSessionRestoreFailed(let message):
            return message
        case .guestSessionRestoreFailedNeedsReset:
            return AppLocalized.localizedSync(L10n.Auth.guestSessionRestoreFailedMessage)
        }
    }

    var needsGuestSessionReset: Bool {
        if case .guestSessionRestoreFailedNeedsReset = self {
            return true
        }
        return false
    }
}
