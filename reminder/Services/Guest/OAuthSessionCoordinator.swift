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
        if GuestSessionStore.loadSnapshot() != nil {
            switch await GuestDataMigrationService.evaluateTrialMigration() {
            case .migrate:
                guard let guestSnapshot = GuestSessionStore.loadSnapshot() else { break }
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
            case .discardReturningUser:
                await GuestDataMigrationService.discardTrialSnapshotWithoutMigration()
            case .keepSnapshotRetryLater:
                break
            }
        }

        await appRouter.refreshStateFromBackend()
        if appRouter.appState == .unauthenticated {
            appRouter.goToOrgRouting()
        } else {
            appRouter.logVIPAccessState(trigger: "用户登录后")
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
