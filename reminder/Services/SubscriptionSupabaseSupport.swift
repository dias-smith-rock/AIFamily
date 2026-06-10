import Foundation

#if canImport(Supabase)
import Supabase
#endif

enum SubscriptionSupabaseSupport {
    private static let entitlementColumns = "user_id,is_pro,pro_expires_at"
    private static let verifyAppleSubscriptionFunction = "verify-apple-subscription"

    /// 最近一次 `household_creator_has_active_pro` 拉取结果，供 VIP 诊断日志使用。
    @MainActor
    private(set) static var lastCreatorProFetchDiagnostics = CreatorProFetchDiagnostics()

    @MainActor
    static func fetchHouseholdCreatorHasActivePro(householdId: UUID) async throws -> Bool {
        #if canImport(Supabase)
        do {
            let value: Bool = try await SupabaseManager.shared.client
                .rpc(
                    "household_creator_has_active_pro",
                    params: HouseholdCreatorHasActiveProParams(pHouseholdId: householdId)
                )
                .execute()
                .value
            lastCreatorProFetchDiagnostics = CreatorProFetchDiagnostics(
                householdId: householdId,
                result: value,
                errorMessage: nil,
                fetchedAt: Date()
            )
            return value
        } catch {
            let message = error.localizedDescription
            lastCreatorProFetchDiagnostics = CreatorProFetchDiagnostics(
                householdId: householdId,
                result: nil,
                errorMessage: message,
                fetchedAt: Date()
            )
            throw error
        }
        #else
        _ = householdId
        throw SubscriptionSupabaseError.sdkUnavailable
        #endif
    }

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
        } catch {
            throw SubscriptionSupabaseError.serverError(Self.serverErrorMessage(from: error))
        }
        #else
        _ = signedTransactionInfo
        _ = environment
        throw SubscriptionSupabaseError.sdkUnavailable
        #endif
    }

    /// 创世用户福利：已禁用客户端直写，须通过服务端发放。
    #if canImport(Supabase)
    private static func serverErrorMessage(from error: Error) -> String {
        if let functionsError = error as? FunctionsError,
           case .httpError(let code, let data) = functionsError {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if let parsed = try? JSONDecoder().decode(VerifyAppleSubscriptionErrorBody.self, from: data),
               let message = parsed.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               message.isEmpty == false {
                #if DEBUG
                if let step = parsed.step?.trimmingCharacters(in: .whitespacesAndNewlines),
                   step.isEmpty == false {
                    return "[\(step)] \(message)"
                }
                #endif
                return message
            }
            if bodyText.isEmpty == false {
                return bodyText
            }
            return "Edge Function HTTP \(code)"
        }
        return error.localizedDescription
    }
    #endif

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

struct CreatorProFetchDiagnostics: Equatable, Sendable {
    var householdId: UUID?
    var result: Bool?
    var errorMessage: String?
    var fetchedAt: Date?

    var summaryForLog: String {
        if let errorMessage, errorMessage.isEmpty == false {
            return "RPC失败: \(errorMessage)"
        }
        if let result {
            let idPrefix = householdId.map { String($0.uuidString.prefix(8)) } ?? "nil"
            return "RPC成功 household=\(idPrefix) result=\(result)"
        }
        return "RPC未调用"
    }
}

struct HouseholdCreatorHasActiveProParams: Encodable, Sendable {
    var pHouseholdId: UUID

    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pHouseholdId.uuidString.lowercased(), forKey: .pHouseholdId)
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
    var step: String?
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
