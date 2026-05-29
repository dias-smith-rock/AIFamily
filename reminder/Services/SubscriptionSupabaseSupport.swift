import Foundation

#if canImport(Supabase)
import Supabase
#endif

enum SubscriptionSupabaseSupport {
    private static let entitlementColumns = "user_id,is_pro,pro_expires_at"

    @MainActor
    static func fetchUserEntitlement(userId: UUID) async throws -> UserEntitlement? {
        #if canImport(Supabase)
        let rows: [UserEntitlement] = try await SupabaseManager.shared.client
            .from("user_entitlements")
            .select(entitlementColumns)
            .eq("user_id", value: userId.uuidString.lowercased())
            .limit(1)
            .execute()
            .value
        return rows.first
        #else
        _ = userId
        throw SubscriptionSupabaseError.sdkUnavailable
        #endif
    }

    /// 创世用户福利：写入订单、个人权益，并将用户作为创建者的群组标记为 Premium。
    @MainActor
    static func claimFreeProTrialForCurrentUser() async throws -> Date {
        #if canImport(Supabase)
        let session = try await SupabaseManager.shared.client.auth.session
        let userId = session.user.id
        return try await claimFreeProTrial(userId: userId)
        #else
        throw SubscriptionSupabaseError.sdkUnavailable
        #endif
    }

    @MainActor
    static func claimFreeProTrial(userId: UUID) async throws -> Date {
        let oneYearLater = Calendar.current.date(byAdding: .year, value: 1, to: Date())
            ?? Date().addingTimeInterval(365 * 24 * 60 * 60)

        #if canImport(Supabase)
        let client = SupabaseManager.shared.client

        let orderPayload = SubscriptionOrderInsertPayload(
            payerId: userId,
            planPurchased: SubscriptionPlan.proOneYearFree.rawValue,
            expiresAt: oneYearLater
        )
        try await client
            .from("subscription_orders")
            .insert(orderPayload)
            .execute()

        let entitlementPayload = UserEntitlementUpsertPayload(
            userId: userId,
            isPro: true,
            proExpiresAt: oneYearLater
        )
        try await client
            .from("user_entitlements")
            .upsert(entitlementPayload)
            .execute()

        let groupUpdate = HouseholdPremiumPatch(isPremium: true)
        try await client
            .from("households")
            .update(groupUpdate)
            .eq("creator_id", value: userId.uuidString.lowercased())
            .execute()

        return oneYearLater
        #else
        _ = userId
        throw SubscriptionSupabaseError.sdkUnavailable
        #endif
    }
}

struct UserEntitlementUpsertPayload: Encodable, Equatable, Sendable {
    var userId: UUID
    var isPro: Bool
    var proExpiresAt: Date?

    init(userId: UUID, isPro: Bool, proExpiresAt: Date?) {
        self.userId = userId
        self.isPro = isPro
        self.proExpiresAt = proExpiresAt
    }
}

private struct HouseholdPremiumPatch: Encodable {
    var isPremium: Bool
}

enum SubscriptionSupabaseError: LocalizedError {
    case sdkUnavailable

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return String(localized: "当前构建环境未包含 Supabase SDK。")
        }
    }
}
