import Foundation

#if canImport(Supabase)
import Supabase
#endif

@MainActor
enum OAuthSessionCoordinator {
    enum SettlementError: LocalizedError {
        case sessionNotReady

        var errorDescription: String? {
            switch self {
            case .sessionNotReady:
                AppLocalized.localizedSync(L10n.Auth.theLoginSessionIsNotReadyYetPleaseTryAg)
            }
        }
    }

    /// OAuth 成功后等待会话就绪并刷新组织路由。
    static func settleAfterOAuth(
        appRouter: AppRouter,
        appBootstrap: AppBootstrap,
        onEnterOrgRouting: @MainActor () -> Void,
        migrationFailureHandler: ((String) -> Void)? = nil
    ) async throws {
        #if canImport(Supabase)
        _ = migrationFailureHandler

        let maxAttempts = 8
        var hasFormalSession = false
        for attempt in 1...maxAttempts {
            do {
                let session = try await SupabaseManager.shared.client.auth.session
                guard session.user.isAnonymous == false else {
                    if attempt == maxAttempts {
                        throw SettlementError.sessionNotReady
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }
                hasFormalSession = true
                break
            } catch {
                if attempt == maxAttempts {
                    throw error
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        guard hasFormalSession else {
            throw SettlementError.sessionNotReady
        }

        AuthSessionHints.markEverAuthenticated()
        appRouter.clearHouseholdRoutingForIdentitySwitch()
        appRouter.beginHouseholdRoutingResolve()
        defer { appRouter.finishHouseholdRoutingResolveAfterRefresh() }

        appRouter.markOAuthBootstrapCompleted()
        appRouter.goToOrgRouting()
        onEnterOrgRouting()

        await appRouter.refreshStateFromBackend()
        await retryOAuthHouseholdRefreshIfNeeded(appRouter: appRouter)
        await SupabaseAuthManager.persistFormalSessionIfNeeded()
        await GuestSessionKeepAlive.refreshAfterOAuthSettlementIfNeeded()
        appBootstrap.bumpSessionRevision()

        if appRouter.appState != .unauthenticated {
            appRouter.logVIPAccessState(trigger: "用户登录后")
        }
        AnalyticsManager.logAuthSessionSucceeded()
        #else
        _ = appRouter
        _ = appBootstrap
        _ = onEnterOrgRouting
        throw SettlementError.sessionNotReady
        #endif
    }

    #if canImport(Supabase)
    /// OAuth 后若仍停在 orgRouting（RLS 传播延迟），对正式账号轻量重试 refresh。
    private static func retryOAuthHouseholdRefreshIfNeeded(appRouter: AppRouter) async {
        guard appRouter.isAnonymousUser == false else { return }
        let maxRetries = 3
        for attempt in 1...maxRetries where appRouter.appState == .orgRouting {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await appRouter.refreshStateFromBackend()
            if appRouter.appState != .orgRouting {
                break
            }
            #if DEBUG
            print("[OAuthSessionCoordinator] oauth household refresh retry \(attempt)/\(maxRetries)")
            #endif
        }
    }
    #endif
}
