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
        migrationFailureHandler: ((String) -> Void)? = nil
    ) async throws {
        #if canImport(Supabase)
        _ = appBootstrap
        _ = migrationFailureHandler

        let maxAttempts = 8
        var hasValidSession = false
        for attempt in 1...maxAttempts {
            do {
                _ = try await SupabaseManager.shared.client.auth.session
                hasValidSession = true
                break
            } catch {
                if attempt == maxAttempts {
                    throw error
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        guard hasValidSession else {
            throw SettlementError.sessionNotReady
        }

        AuthSessionHints.markEverAuthenticated()
        await appRouter.refreshStateFromBackend()
        if appRouter.appState == .unauthenticated {
            appRouter.goToOrgRouting()
        } else {
            appRouter.logVIPAccessState(trigger: "用户登录后")
        }
        AnalyticsManager.logAuthSessionSucceeded()
        #else
        _ = appRouter
        _ = appBootstrap
        throw SettlementError.sessionNotReady
        #endif
    }
}
