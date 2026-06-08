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
                "登录会话尚未就绪，请稍后重试。"
            }
        }
    }

    /// OAuth 成功后：可选迁移游客快照 → 切换 Live 服务 → 刷新组织路由。
    /// - Returns: 游客数据迁移是否失败（快照仍保留，可重试）。
    @discardableResult
    static func settleAfterOAuth(
        appRouter: AppRouter,
        appBootstrap: AppBootstrap,
        migrationFailureHandler: ((String) -> Void)? = nil
    ) async throws -> Bool {
        #if canImport(Supabase)
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
        appBootstrap.enterLiveMode()

        var migrationFailed = false
        if let guestSnapshot = GuestSessionStore.loadSnapshot() {
            do {
                _ = try await GuestDataMigrationService.migrate(
                    snapshot: guestSnapshot,
                    appRouter: appRouter
                )
            } catch {
                migrationFailed = true
                CrashReporting.record(error, context: ["step": "guest_migration"])
                migrationFailureHandler?(error.localizedDescription)
            }
        }

        await appRouter.refreshStateFromBackend()
        if appRouter.appState == .unauthenticated {
            appRouter.goToOrgRouting()
        }
        AnalyticsManager.logAuthSessionSucceeded()
        return migrationFailed
        #else
        _ = appRouter
        _ = appBootstrap
        throw SettlementError.sessionNotReady
        #endif
    }
}
