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
        OAuthLoginPerformanceTracer.mark("oauth.settle.begin", appRouter: appRouter)

        let maxAttempts = 8
        var hasFormalSession = false
        for attempt in 1...maxAttempts {
            OAuthLoginPerformanceTracer.mark(
                "oauth.settle.sessionPoll",
                note: "attempt=\(attempt)/\(maxAttempts)",
                appRouter: appRouter
            )
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
                OAuthLoginPerformanceTracer.mark(
                    "oauth.settle.sessionReady",
                    note: "userId=\(session.user.id.uuidString.lowercased())",
                    appRouter: appRouter
                )
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
        appRouter.markOAuthBootstrapCompleted()

        await OAuthLoginPerformanceTracer.measure(
            "oauth.settle.refreshStateFromBackend",
            appRouter: appRouter
        ) {
            await appRouter.refreshStateFromBackend()
        }
        await OAuthLoginPerformanceTracer.measure(
            "oauth.settle.retryHouseholdRefresh",
            appRouter: appRouter
        ) {
            await retryOAuthHouseholdRefreshIfNeeded(appRouter: appRouter)
        }

        enterAuthenticatedUIAfterOAuthRefresh(
            appRouter: appRouter,
            onEnterOrgRouting: onEnterOrgRouting
        )

        await OAuthLoginPerformanceTracer.measure(
            "oauth.settle.persistFormalSession",
            appRouter: appRouter
        ) {
            await SupabaseAuthManager.persistFormalSessionIfNeeded()
        }
        await OAuthLoginPerformanceTracer.measure(
            "oauth.settle.guestKeepAliveRefresh",
            appRouter: appRouter
        ) {
            await GuestSessionKeepAlive.refreshAfterOAuthSettlementIfNeeded()
        }
        appBootstrap.bumpSessionRevision()
        OAuthLoginPerformanceTracer.mark(
            "oauth.settle.end",
            note: "appState=\(appRouter.appState.perfTraceName)",
            appRouter: appRouter
        )

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
    /// refresh 完成后按 `appState` 进入已登录 UI；直达 activeMember 时不经过 orgRouting。
    private static func enterAuthenticatedUIAfterOAuthRefresh(
        appRouter: AppRouter,
        onEnterOrgRouting: @MainActor () -> Void
    ) {
        switch appRouter.appState {
        case .activeMember:
            OAuthLoginPerformanceTracer.mark(
                "oauth.settle.route.activeMember",
                note: "skipOrgRouting",
                appRouter: appRouter
            )
            OAuthLoginPerformanceTracer.mark("oauth.settle.beforeEnterOrgRouting", appRouter: appRouter)
            onEnterOrgRouting()
            OAuthLoginPerformanceTracer.mark("oauth.settle.afterEnterOrgRouting", appRouter: appRouter)
        case .orgRouting:
            appRouter.beginHouseholdRoutingResolve()
            appRouter.finishHouseholdRoutingResolveAfterRefresh()
            OAuthLoginPerformanceTracer.mark("oauth.settle.goToOrgRouting", appRouter: appRouter)
            OAuthLoginPerformanceTracer.mark("oauth.settle.beforeEnterOrgRouting", appRouter: appRouter)
            onEnterOrgRouting()
            OAuthLoginPerformanceTracer.mark("oauth.settle.afterEnterOrgRouting", appRouter: appRouter)
        case .householdSelection, .pendingApproval:
            OAuthLoginPerformanceTracer.mark(
                "oauth.settle.route.\(appRouter.appState.perfTraceName)",
                appRouter: appRouter
            )
            OAuthLoginPerformanceTracer.mark("oauth.settle.beforeEnterOrgRouting", appRouter: appRouter)
            onEnterOrgRouting()
            OAuthLoginPerformanceTracer.mark("oauth.settle.afterEnterOrgRouting", appRouter: appRouter)
        case .unauthenticated:
            appRouter.beginHouseholdRoutingResolve()
            appRouter.finishHouseholdRoutingResolveAfterRefresh()
            appRouter.goToOrgRouting()
            OAuthLoginPerformanceTracer.mark("oauth.settle.goToOrgRouting", note: "fallback", appRouter: appRouter)
            OAuthLoginPerformanceTracer.mark("oauth.settle.beforeEnterOrgRouting", appRouter: appRouter)
            onEnterOrgRouting()
            OAuthLoginPerformanceTracer.mark("oauth.settle.afterEnterOrgRouting", appRouter: appRouter)
        }
    }

    /// OAuth 后若仍停在 orgRouting（RLS 传播延迟），对正式账号轻量重试 refresh。
    private static func retryOAuthHouseholdRefreshIfNeeded(appRouter: AppRouter) async {
        guard appRouter.isAnonymousUser == false else { return }
        let maxRetries = 3
        for attempt in 1...maxRetries where appRouter.appState == .orgRouting {
            OAuthLoginPerformanceTracer.mark(
                "oauth.settle.retryHouseholdRefresh.attempt",
                note: "attempt=\(attempt)/\(maxRetries)",
                appRouter: appRouter
            )
            try? await Task.sleep(nanoseconds: 400_000_000)
            await appRouter.refreshStateFromBackend()
            if appRouter.appState != .orgRouting {
                OAuthLoginPerformanceTracer.mark(
                    "oauth.settle.retryHouseholdRefresh.resolved",
                    note: "appState=\(appRouter.appState.perfTraceName)",
                    appRouter: appRouter
                )
                break
            }
            #if DEBUG
            print("[OAuthSessionCoordinator] oauth household refresh retry \(attempt)/\(maxRetries)")
            #endif
        }
    }
    #endif
}
