import Foundation
#if canImport(Supabase)
import Supabase
#endif

@MainActor
enum AuthSessionRefresher {
    /// App 进入前台时用 refresh token 续期；后台期间 Supabase 自动刷新计时器会暂停。
    /// - Returns: `true` 表示 refresh 因鉴权失败（应踢回登录）；离线/无 session 返回 `false`。
    @discardableResult
    static func refreshOnForegroundIfNeeded() async -> Bool {
        #if canImport(Supabase)
        LoginFlowPerformanceTracing.mark("authSessionRefresher.begin")
        guard AuthSessionGuard.shared.isLoggingOut == false else {
            LoginFlowPerformanceTracing.mark("authSessionRefresher.skip", note: "isLoggingOut")
            return false
        }
        _ = await NetworkMonitor.shared.ensureInitialPathReady()
        guard await NetworkMonitor.shared.isConnected else {
            LoginFlowPerformanceTracing.mark("authSessionRefresher.skip", note: "offline")
            return false
        }
        let client = SupabaseManager.shared.client
        guard client.auth.currentSession != nil else {
            LoginFlowPerformanceTracing.mark("authSessionRefresher.skip", note: "noCurrentSession")
            return false
        }
        do {
            _ = try await client.auth.refreshSession()
            LoginFlowPerformanceTracing.mark("authSessionRefresher.ok")
            #if DEBUG
            print("[AuthSessionRefresher] refreshSession ok")
            #endif
            return false
        } catch {
            LoginFlowPerformanceTracing.mark(
                "authSessionRefresher.failed",
                note: error.localizedDescription
            )
            #if DEBUG
            print("[AuthSessionRefresher] refreshSession failed: \(error.localizedDescription)")
            #endif
            CrashReporting.record(error, context: ["step": "foreground_session_refresh"])
            return isLikelyAuthenticationFailure(error)
        }
        #else
        return false
        #endif
    }

    private static func isLikelyAuthenticationFailure(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        if text.contains("invalid refresh")
            || text.contains("refresh_token")
            || text.contains("session") && text.contains("expired")
            || text.contains("jwt")
            || text.contains("not authenticated")
            || text.contains("unauthorized")
            || text.contains("401") {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return false }
        return false
    }
}
