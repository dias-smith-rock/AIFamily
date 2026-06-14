import Foundation

#if canImport(Supabase)
import Supabase
#endif

/// 在正式账号在线或登录页停留期间，侧信道保活游客 Keychain 槽位中的 refresh token。
enum GuestSessionKeepAlive {
    static func refreshOnLoginScreenIfNeeded() async {
        guard GuestSessionArchive.hasSavedTokens else { return }
        _ = await GuestArchiveTokenRefresher.refreshArchivedGuestTokens(context: "loginScreen")
    }

    static func refreshWhileFormalUserActiveIfNeeded() async {
        guard GuestSessionArchive.hasSavedTokens else { return }
        #if canImport(Supabase)
        guard let session = try? await SupabaseManager.shared.client.auth.session,
              session.user.isAnonymous == false
        else {
            return
        }
        #endif
        _ = await GuestArchiveTokenRefresher.refreshArchivedGuestTokens(context: "formalUserActive")
    }

    static func refreshAfterOAuthSettlementIfNeeded() async {
        guard GuestSessionArchive.hasSavedTokens else { return }
        _ = await GuestArchiveTokenRefresher.refreshArchivedGuestTokens(context: "oauthSettlement")
    }
}
