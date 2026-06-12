import Foundation

enum SupabaseServiceError: LocalizedError, Equatable {
    case sdkUnavailable
    case invalidConfiguration
    case invalidResponse
    case unsupportedOperation

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
        }
    }
}
