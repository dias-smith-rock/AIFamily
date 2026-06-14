import Foundation
#if canImport(Supabase)
import Supabase
#endif

@MainActor
enum AuthSessionRefresher {
    /// App 进入前台时用 refresh token 续期；后台期间 Supabase 自动刷新计时器会暂停。
    static func refreshOnForegroundIfNeeded() async {
        #if canImport(Supabase)
        AutoLoginPerformanceTracer.mark("authSessionRefresher.begin")
        guard AuthSessionGuard.shared.isLoggingOut == false else {
            AutoLoginPerformanceTracer.mark("authSessionRefresher.skip", note: "isLoggingOut")
            return
        }
        _ = await NetworkMonitor.shared.ensureInitialPathReady()
        guard await NetworkMonitor.shared.isConnected else {
            AutoLoginPerformanceTracer.mark("authSessionRefresher.skip", note: "offline")
            return
        }
        let client = SupabaseManager.shared.client
        guard client.auth.currentSession != nil else {
            AutoLoginPerformanceTracer.mark("authSessionRefresher.skip", note: "noCurrentSession")
            return
        }
        do {
            _ = try await client.auth.refreshSession()
            AutoLoginPerformanceTracer.mark("authSessionRefresher.ok")
            #if DEBUG
            print("[AuthSessionRefresher] refreshSession ok")
            #endif
        } catch {
            AutoLoginPerformanceTracer.mark(
                "authSessionRefresher.failed",
                note: error.localizedDescription
            )
            #if DEBUG
            print("[AuthSessionRefresher] refreshSession failed: \(error.localizedDescription)")
            #endif
            CrashReporting.record(error, context: ["step": "foreground_session_refresh"])
        }
        #endif
    }
}
