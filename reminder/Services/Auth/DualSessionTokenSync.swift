import Foundation

#if canImport(Supabase)
import Supabase
#endif

/// 监听 Supabase auth 事件，将最新 token 同步到游客 / 正式 Keychain 槽位。
enum DualSessionTokenSync {
    #if canImport(Supabase)
    private static var listenerTask: Task<Void, Never>?
    #endif

    static func registerIfNeeded() {
        #if canImport(Supabase)
        guard listenerTask == nil else { return }
        listenerTask = Task {
            for await (event, session) in SupabaseManager.shared.client.auth.authStateChanges {
                await MainActor.run {
                    handleAuthStateChange(event: event, session: session)
                }
            }
        }
        #endif
    }

    #if canImport(Supabase)
    @MainActor
    private static func handleAuthStateChange(event: AuthChangeEvent, session: Session?) {
        guard let session, session.refreshToken.isEmpty == false else { return }
        switch event {
        case .signedIn, .tokenRefreshed, .initialSession:
            SupabaseAuthManager.persistSessionToDualStore(session)
            if session.user.isAnonymous == false, GuestSessionArchive.hasSavedTokens {
                Task {
                    _ = await GuestArchiveTokenRefresher.refreshArchivedGuestTokens(
                        context: "dualSessionSync.\(event)"
                    )
                }
            }
        case .signedOut, .passwordRecovery, .userUpdated, .userDeleted, .mfaChallengeVerified:
            break
        }
    }
    #endif
}
