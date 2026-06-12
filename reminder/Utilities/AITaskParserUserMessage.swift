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

        return L10n.Common.photoRecognitionFailedPleaseTryAgainLater.string()
    }

    static func mapServerRawText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let lower = trimmed.lowercased()

        if isModelUnavailable(lower) {
            return L10n.Common.aiPhotoRecognitionIsTemporarilyUnavailable.string()
        }
        if isRateLimited(lower) {
            return L10n.Common.tooManyRequestsPleaseTryAgainLater.string()
        }
        if isServiceMisconfigured(lower) {
            return L10n.Common.aiPhotoRecognitionIsNotFullySetUpYetTry.string()
        }
        if isTaskExtractionFailure(lower) {
            return L10n.Schedule.couldnTExtractAValidTaskFromThePhotoTry.string()
        }
        if isUploadParameterFailure(lower) {
            return L10n.Common.thereWasAProblemUploadingThePhotoPleaseT.string()
        }
        if isNetworkFailure(lower) {
            return L10n.Common.networkConnectionIssueCheckYourConnectionA.string()
        }
        if isAuthFailure(lower) {
            return L10n.Auth.yourSignInSessionExpiredPleaseSignInAgai.string()
        }

        if looksLikeTechnicalError(trimmed) {
            return L10n.Common.photoRecognitionFailedPleaseTryAgainLater.string()
        }

        return nil
    }

    private static func message(forHTTPStatus code: Int) -> String {
        switch code {
        case 502, 503, 504:
            return L10n.Common.aiPhotoRecognitionIsTemporarilyUnavailable.string()
        case 429:
            return L10n.Common.tooManyRequestsPleaseTryAgainLater.string()
        case 401, 403:
            return L10n.Auth.yourSignInSessionExpiredPleaseSignInAgai.string()
        default:
            return L10n.Common.photoRecognitionFailedPleaseTryAgainLater.string()
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
            return L10n.Common.networkConnectionIssueCheckYourConnectionA.string()
        default:
            return L10n.Common.photoRecognitionFailedPleaseTryAgainLater.string()
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
            return L10n.Common.supabaseSdkIsNotAvailableInThisBuild.string()
        case .notAuthenticated:
            return L10n.Auth.pleaseLogInFirstBeforeUsingAiToCreateA.string()
        case .uploadFailed(_, let isStorageRLS):
            if isStorageRLS {
                return L10n.Common.uploadFailedStoragePermissionsAreNotConfig.string()
            }
            return L10n.Common.imageUploadFailedPleaseCheckTheNetworkAnd.string()
        case .invalidResponse:
            return L10n.Common.couldNotParseTheDataReturnedByAiPleaseT.string()
        case .serverError(let message):
            return AITaskParserUserMessage.mapServerRawText(message)
                ?? L10n.Common.photoRecognitionFailedPleaseTryAgainLater.string()
        }
    }
}
