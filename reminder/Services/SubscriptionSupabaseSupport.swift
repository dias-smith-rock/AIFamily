import Foundation

#if canImport(Supabase)
import Supabase
#endif

enum SubscriptionSupabaseSupport {
    private static let entitlementColumns = "user_id,is_pro,pro_expires_at"
    private static let verifyAppleSubscriptionFunction = "verify-apple-subscription"

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

    /// App Store 购买/恢复/续订：服务端校验 JWS 后由 Edge Function 写入订单与权益。
    @MainActor
    static func activatePremiumFromApplePurchase(
        signedTransactionInfo: String,
        environment: String
    ) async throws -> VerifyAppleSubscriptionResponse {
        #if canImport(Supabase)
        let client = SupabaseManager.shared.client
        let request = VerifyAppleSubscriptionRequest(
            signedTransactionInfo: signedTransactionInfo,
            environment: environment
        )

        do {
            return try await client.functions.invoke(
                verifyAppleSubscriptionFunction,
                options: FunctionInvokeOptions(body: request)
            )
        } catch let error as FunctionsError {
            if case .httpError(_, let data) = error,
               let parsed = try? JSONDecoder().decode(VerifyAppleSubscriptionErrorBody.self, from: data),
               let message = parsed.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               message.isEmpty == false {
                throw SubscriptionSupabaseError.serverError(message)
            }
            throw SubscriptionSupabaseError.serverError(error.localizedDescription)
        } catch {
            throw SubscriptionSupabaseError.serverError(error.localizedDescription)
        }
        #else
        _ = signedTransactionInfo
        _ = environment
        throw SubscriptionSupabaseError.sdkUnavailable
        #endif
    }

    /// 创世用户福利：已禁用客户端直写，须通过服务端发放。
    @MainActor
    static func claimFreeProTrialForCurrentUser() async throws -> Date {
        throw SubscriptionSupabaseError.promotionalGrantDisabled
    }

    @MainActor
    static func claimFreeProTrial(userId: UUID) async throws -> Date {
        _ = userId
        throw SubscriptionSupabaseError.promotionalGrantDisabled
    }
}

struct VerifyAppleSubscriptionRequest: Encodable, Sendable {
    var signedTransactionInfo: String
    var environment: String
}

struct VerifyAppleSubscriptionResponse: Decodable, Sendable, Equatable {
    var success: Bool?
    var plan: String?
    var productId: String?
    var transactionId: String?
    var expiresAt: String?
}

private struct VerifyAppleSubscriptionErrorBody: Decodable {
    var error: String?
}

enum SubscriptionSupabaseError: LocalizedError {
    case sdkUnavailable
    case serverError(String)
    case promotionalGrantDisabled

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return String(localized: "当前构建环境未包含 Supabase SDK。")
        case .serverError(let message):
            return message
        case .promotionalGrantDisabled:
            return String(localized: "促销权益须由服务端发放，客户端无法直接领取。")
        }
    }
}
