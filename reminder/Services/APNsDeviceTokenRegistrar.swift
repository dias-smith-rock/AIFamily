import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(Supabase)
import Supabase
#endif

/// Registers the APNs device token with Supabase `user_device_tokens` after notification auth.
@MainActor
enum APNsDeviceTokenRegistrar {
    private static let lastTokenDefaultsKey = "apns.lastDeviceTokenHex"

    #if DEBUG
    private static func debugLog(_ message: String) {
        print("[APNsDeviceTokenRegistrar] \(message)")
    }
    #else
    private static func debugLog(_ message: String) {}
    #endif

    /// Request notification permission (if needed) then register for remote notifications.
    static func requestAuthorizationAndRegister() async {
        #if canImport(UIKit)
        debugLog("begin requestAuthorizationAndRegister")
        let granted = await NotificationManager.shared.requestAuthorizationIfNeeded()
        guard granted else {
            debugLog("skip register: notification not authorized")
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
        debugLog("registerForRemoteNotifications called")
        #endif
    }

    static func handleDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        guard hex.isEmpty == false else { return }
        debugLog("didRegister tokenPrefix=\(hex.prefix(8)) bytes=\(deviceToken.count)")
        UserDefaults.standard.set(hex, forKey: lastTokenDefaultsKey)
        Task {
            await upsertToken(hex)
        }
    }

    static func handleRegistrationFailure(_ error: Error) {
        debugLog("didFailToRegister: \(error.localizedDescription)")
    }

    /// Best-effort delete of this device's token row before sign-out.
    static func clearCurrentDeviceToken() async {
        #if canImport(Supabase)
        let hex = UserDefaults.standard.string(forKey: lastTokenDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        defer { UserDefaults.standard.removeObject(forKey: lastTokenDefaultsKey) }
        guard hex.isEmpty == false else { return }
        guard let userId = await SupabaseAuthManager.currentUserId() else { return }
        do {
            try await SupabaseManager.shared.client
                .from("user_device_tokens")
                .delete()
                .eq("user_id", value: userId.uuidString.lowercased())
                .eq("apns_token", value: hex)
                .execute()
            debugLog("deleted token for user=\(userId.uuidString.prefix(8))")
        } catch {
            debugLog("delete failed: \(error.localizedDescription)")
        }
        #endif
    }

    private static func upsertToken(_ hex: String) async {
        #if canImport(Supabase)
        guard await SupabaseAuthManager.isAnonymousUser() == false else {
            debugLog("skip upsert: anonymous user")
            return
        }
        guard let userId = await SupabaseAuthManager.currentUserId() else {
            debugLog("skip upsert: no session")
            return
        }

        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif

        struct Payload: Encodable {
            let userId: UUID
            let apnsToken: String
            let platform: String
            let environment: String
            let updatedAt: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case apnsToken = "apns_token"
                case platform
                case environment
                case updatedAt = "updated_at"
            }
        }

        let payload = Payload(
            userId: userId,
            apnsToken: hex,
            platform: "ios",
            environment: environment,
            updatedAt: Date().postgresTimestamptzString
        )

        do {
            try await SupabaseManager.shared.client
                .from("user_device_tokens")
                .upsert(payload, onConflict: "user_id,apns_token")
                .execute()
            debugLog(
                "upsert ok user=\(userId.uuidString.prefix(8)) env=\(environment) tokenPrefix=\(hex.prefix(8))"
            )
        } catch {
            debugLog("upsert failed: \(error.localizedDescription)")
        }
        #endif
    }
}
