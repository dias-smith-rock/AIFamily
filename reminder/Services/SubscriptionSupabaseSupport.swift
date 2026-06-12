import Foundation

#if canImport(Supabase)
import Supabase
#endif

enum SubscriptionSupabaseSupport {
    private static let entitlementColumns = "user_id,is_pro,pro_expires_at"
    private static let syncRevenueCatEntitlementFunction = "sync-revenuecat-entitlement"

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

    /// 客户端兜底：服务端用 RevenueCat Secret API 校验后写入 `user_entitlements`。
    @MainActor
    static func syncEntitlementFromRevenueCat() async throws -> SyncRevenueCatEntitlementResponse {
        #if canImport(Supabase)
        let client = SupabaseManager.shared.client
        do {
            return try await client.functions.invoke(
                syncRevenueCatEntitlementFunction,
                options: FunctionInvokeOptions(body: SyncRevenueCatEntitlementRequest())
            )
        } catch {
            throw SubscriptionSupabaseError.serverError(Self.serverErrorMessage(from: error))
        }
        #else
        throw SubscriptionSupabaseError.sdkUnavailable
        #endif
    }

    #if canImport(Supabase)
    private static func serverErrorMessage(from error: Error) -> String {
        if let functionsError = error as? FunctionsError,
           case .httpError(let code, let data) = functionsError {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if let parsed = try? JSONDecoder().decode(SubscriptionFunctionErrorBody.self, from: data),
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

struct SyncRevenueCatEntitlementRequest: Encodable, Sendable {}

struct SyncRevenueCatEntitlementResponse: Decodable, Sendable, Equatable {
    var synced: Bool?
    var isPro: Bool?
    var proExpiresAt: String?
    var planPurchased: String?

    enum CodingKeys: String, CodingKey {
        case synced
        case isPro
        case proExpiresAt
        case planPurchased
    }
}

private struct SubscriptionFunctionErrorBody: Decodable {
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
            return AppLocalized.localizedSync(L10n.Common.supabaseSdkIsNotAvailableInThisBuild)
        case .serverError(let message):
            return message
        case .promotionalGrantDisabled:
            return AppLocalized.localizedSync(L10n.Common.promotionalBenefitsMustBeGrantedByTheServ)
        }
    }
}
