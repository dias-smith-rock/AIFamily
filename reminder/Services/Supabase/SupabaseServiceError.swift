import Foundation

enum SupabaseServiceError: LocalizedError, Equatable {
    case sdkUnavailable
    case invalidConfiguration
    case invalidResponse
    case unsupportedOperation

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return AppLocalized.localizedSync("Supabase SDK 尚未接入，请先添加依赖。")
        case .invalidConfiguration:
            return AppLocalized.localizedSync("Supabase 配置无效，请检查 URL 与 Anon Key。")
        case .invalidResponse:
            return AppLocalized.localizedSync("服务返回数据异常。")
        case .unsupportedOperation:
            return AppLocalized.localizedSync("当前操作尚未实现。")
        }
    }
}
