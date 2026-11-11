import Foundation

enum SupabaseServiceError: LocalizedError, Equatable {
    case sdkUnavailable
    case invalidConfiguration
    case invalidResponse
    case unsupportedOperation
    /// RLS 过滤后 0 行：PostgREST 删除常「成功」但不改数据。
    case deleteNotPermittedOrMissing

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return AppLocalized.localizedSync(L10n.Common.supabaseSdkIsNotAvailableInThisBuildPlea)
        case .invalidConfiguration:
            return AppLocalized.localizedSync(L10n.Common.invalidSupabaseConfigurationPleaseCheckThe)
        case .invalidResponse:
            return AppLocalized.localizedSync(L10n.Common.unexpectedResponseFromTheServer)
        case .unsupportedOperation:
            return AppLocalized.localizedSync(L10n.Common.thisOperationIsNotImplementedYet)
        case .deleteNotPermittedOrMissing:
            return AppLocalized.localizedSync(L10n.Common.youDonTHavePermissionToPerformThisAction)
        }
    }
}
