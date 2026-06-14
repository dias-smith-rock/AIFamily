import Foundation
import RevenueCat

#if canImport(Supabase)
import Supabase
#endif

/// 客户端主动自愈：将 RevenueCat 本机订阅状态 upsert 至 `user_entitlements`。
@MainActor
final class SubscriptionTrigger {
    static let shared = SubscriptionTrigger()

    private init() {}

    func syncSubscriptionFallback(appRouter: AppRouter? = nil) async {
        #if canImport(Supabase)
        guard RevenueCatSubscriptionService.shared.isConfigured else {
            #if DEBUG
            print("[SubscriptionTrigger] skipped: RevenueCat not configured")
            #endif
            return
        }

        guard let userId = await SupabaseAuthManager.currentUserId() else {
            #if DEBUG
            print("[SubscriptionTrigger] skipped: no Supabase session")
            #endif
            return
        }

        do {
            let info = try await Purchases.shared.customerInfo()
            let state = resolvePremiumState(from: info)
            let payload = UserEntitlementUpsertPayload(
                userId: userId,
                isPro: state.isActive,
                proExpiresAt: state.expiresAt?.postgresTimestamptzString
            )

            try await SupabaseManager.shared.client
                .from("user_entitlements")
                .upsert(payload, onConflict: "user_id")
                .execute()

            if let appRouter {
                await appRouter.refreshPremiumStateAfterClaim()
            }

            #if DEBUG
            print(
                "[SubscriptionTrigger] upsert ok userId=\(userId.uuidString.prefix(8)) " +
                "isPro=\(state.isActive) expires=\(payload.proExpiresAt ?? "nil")"
            )
            #endif
        } catch {
            #if DEBUG
            print("[SubscriptionTrigger] sync failed: \(error.localizedDescription)")
            #endif
        }
        #else
        _ = appRouter
        #endif
    }

    private func resolvePremiumState(from info: CustomerInfo) -> (isActive: Bool, expiresAt: Date?) {
        if let entitlement = info.entitlements[RevenueCatConfiguration.premiumEntitlementID],
           entitlement.isActive {
            return (true, entitlement.expirationDate)
        }
        for productId in StoreKitProductCatalog.allProductIDs where info.activeSubscriptions.contains(productId) {
            return (true, info.expirationDate(forProductIdentifier: productId))
        }
        return (false, nil)
    }
}

/// 写入 `user_entitlements`（RLS：`user_id = auth.uid()`）。
struct UserEntitlementUpsertPayload: Encodable, Sendable {
    var userId: UUID
    var isPro: Bool
    var proExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case isPro = "is_pro"
        case proExpiresAt = "pro_expires_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId.uuidString.lowercased(), forKey: .userId)
        try container.encode(isPro, forKey: .isPro)
        try container.encodeIfPresent(proExpiresAt, forKey: .proExpiresAt)
    }
}
