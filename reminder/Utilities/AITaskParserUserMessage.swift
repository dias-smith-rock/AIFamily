import Foundation

#if canImport(Supabase)
import Supabase
#endif

/// 将 AI 识图链路中的底层 / 服务端错误转为用户可读文案（中文 Key → String Catalog）。
enum AITaskParserUserMessage {
    static func message(for error: Error) -> String {
        if let parserError = error as? AITaskParserError {
            return parserError.userFacingMessage
        }

        #if canImport(Supabase)
        if let functionsError = error as? FunctionsError,
           case .httpError(let code, let data) = functionsError {
            let body = String(data: data, encoding: .utf8) ?? ""
            if let parsed = try? JSONDecoder().decode(AIEdgeFunctionErrorEnvelope.self, from: data),
               let serverText = parsed.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               serverText.isEmpty == false,
               let mapped = mapServerRawText(serverText) {
                return mapped
            }
            if let mapped = mapServerRawText(body) {
                return mapped
            }
            return message(forHTTPStatus: code)
        }
        #endif

        if let urlError = error as? URLError {
            return message(forURLError: urlError)
        }

        if let mapped = mapServerRawText(error.localizedDescription) {
            return mapped
        }

        return String(localized: "识图失败，请稍后再试。")
    }

    static func mapServerRawText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let lower = trimmed.lowercased()

        if isModelUnavailable(lower) {
            return String(localized: "AI 识图服务暂时不可用，请稍后再试。")
        }
        if isRateLimited(lower) {
            return String(localized: "请求过于频繁，请稍后再试。")
        }
        if isServiceMisconfigured(lower) {
            return String(localized: "AI 识图服务暂未完成配置，请稍后再试或联系管理员。")
        }
        if isTaskExtractionFailure(lower) {
            return String(localized: "未能从图片中提取有效任务信息，请换一张更清晰的照片或手动创建。")
        }
        if isUploadParameterFailure(lower) {
            return String(localized: "图片上传异常，请重试。")
        }
        if isNetworkFailure(lower) {
            return String(localized: "网络连接异常，请检查网络后重试。")
        }
        if isAuthFailure(lower) {
            return String(localized: "登录状态已失效，请重新登录后再试。")
        }

        if looksLikeTechnicalError(trimmed) {
            return String(localized: "识图失败，请稍后再试。")
        }

        return nil
    }

    private static func message(forHTTPStatus code: Int) -> String {
        switch code {
        case 502, 503, 504:
            return String(localized: "AI 识图服务暂时不可用，请稍后再试。")
        case 429:
            return String(localized: "请求过于频繁，请稍后再试。")
        case 401, 403:
            return String(localized: "登录状态已失效，请重新登录后再试。")
        default:
            return String(localized: "识图失败，请稍后再试。")
        }
    }

    private static func message(forURLError error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return String(localized: "网络连接异常，请检查网络后重试。")
        default:
            return String(localized: "识图失败，请稍后再试。")
        }
    }

    private static func isModelUnavailable(_ lower: String) -> Bool {
        lower.contains("503")
            || lower.contains("unavailable")
            || lower.contains("overloaded")
            || lower.contains("overload")
            || lower.contains("high concurrency")
            || lower.contains("节点高并发")
            || lower.contains("server busy")
            || lower.contains("model is overloaded")
            || lower.contains("resource exhausted")
            || lower.contains("capacity")
    }

    private static func isRateLimited(_ lower: String) -> Bool {
        lower.contains("429")
            || lower.contains("rate limit")
            || lower.contains("too many requests")
            || lower.contains("quota")
            || lower.contains("free tier")
    }

    private static func isServiceMisconfigured(_ lower: String) -> Bool {
        lower.contains("api key")
            || lower.contains("not configured")
            || lower.contains("未配置")
            || lower.contains("secret")
    }

    private static func isTaskExtractionFailure(_ lower: String) -> Bool {
        lower.contains("task json parse failed")
            || lower.contains("returned empty content")
            || lower.contains("returned empty")
            || lower.contains("返回空")
            || lower.contains("no text")
    }

    private static func isUploadParameterFailure(_ lower: String) -> Bool {
        lower.contains("missing required parameter")
            || lower.contains("image_url")
    }

    private static func isNetworkFailure(_ lower: String) -> Bool {
        lower.contains("network")
            || lower.contains("timed out")
            || lower.contains("timeout")
            || lower.contains("connection")
    }

    private static func isAuthFailure(_ lower: String) -> Bool {
        lower.contains("not_authenticated")
            || lower.contains("jwt")
            || lower.contains("unauthorized")
    }

    private static func looksLikeTechnicalError(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if raw.contains("API ") || raw.contains("api ") { return true }
        if lower.contains("http") { return true }
        if lower.contains("json") && lower.contains("parse") { return true }
        if lower.contains("ocr-stage") || lower.contains("deepseek") || lower.contains("gemini") { return true }
        if raw.contains("{") && raw.contains("}") { return true }
        return false
    }
}

private struct AIEdgeFunctionErrorEnvelope: Decodable {
    let error: String?
}

extension AITaskParserError {
    var userFacingMessage: String {
        switch self {
        case .sdkUnavailable:
            return String(localized: "当前构建环境未包含 Supabase SDK。")
        case .notAuthenticated:
            return String(localized: "请先登录后再使用 AI 识图创建任务。")
        case .uploadFailed(_, let isStorageRLS):
            if isStorageRLS {
                return String(localized: "图片上传失败，服务器存储权限未配置。请联系管理员在 Supabase 为 create-task-from-images 桶添加写入策略。")
            }
            return String(localized: "图片上传失败，请检查网络后重试。")
        case .invalidResponse:
            return String(localized: "AI 返回的数据无法解析，请重试。")
        case .serverError(let message):
            return AITaskParserUserMessage.mapServerRawText(message)
                ?? String(localized: "识图失败，请稍后再试。")
        }
    }
}
