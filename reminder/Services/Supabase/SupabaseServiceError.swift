import Foundation

enum SupabaseServiceError: LocalizedError, Equatable {
    case sdkUnavailable
    case invalidConfiguration
    case invalidResponse
    case unsupportedOperation

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return "Supabase SDK 尚未接入，请先添加依赖。"
        case .invalidConfiguration:
            return "Supabase 配置无效，请检查 URL 与 Anon Key。"
        case .invalidResponse:
            return "服务返回数据异常。"
        case .unsupportedOperation:
            return "当前操作尚未实现。"
        }
    }
}
