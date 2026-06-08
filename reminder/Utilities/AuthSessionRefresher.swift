import Foundation
#if canImport(Supabase)
import Supabase
#endif

@MainActor
enum AuthSessionRefresher {
    /// App 进入前台时用 refresh token 续期；后台期间 Supabase 自动刷新计时器会暂停。
    static func refreshOnForegroundIfNeeded() async {
        #if canImport(Supabase)
        guard AuthSessionGuard.shared.isLoggingOut == false else { return }
        guard await NetworkMonitor.shared.isConnected else { return }
        let client = SupabaseManager.shared.client
        guard client.auth.currentSession != nil else { return }
        do {
            _ = try await client.auth.refreshSession()
        } catch {
            CrashReporting.record(error, context: ["step": "foreground_session_refresh"])
        }
        #endif
    }
}
