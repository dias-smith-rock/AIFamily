import Foundation
import os

#if canImport(Supabase)
import Supabase
#endif

/// 拍照 / 相册识图创建任务：分步日志（Console + os.Logger），便于定位失败环节。
enum AIPhotoTaskCreationLogger {
    enum Step: String, Sendable {
        case flowStarted = "flow_started"
        case imageCaptured = "image_captured"
        case compressionFailed = "compression_failed"
        case compressionDone = "compression_done"
        case authSessionReady = "auth_session_ready"
        case storageUploadStarted = "storage_upload_started"
        case storageUploadSucceeded = "storage_upload_succeeded"
        case storageUploadFailed = "storage_upload_failed"
        case storageDeleteSucceeded = "storage_delete_succeeded"
        case storageDeleteFailed = "storage_delete_failed"
        case publicURLResolved = "public_url_resolved"
        case edgeFunctionStarted = "edge_function_started"
        case edgeFunctionSucceeded = "edge_function_succeeded"
        case edgeFunctionFailed = "edge_function_failed"
        case parseResponseInvalid = "parse_response_invalid"
        case parseResponseSucceeded = "parse_response_succeeded"
        case ocrExtractLogged = "ocr_extract_logged"
        case prefilledDraftReady = "prefilled_draft_ready"
        case flowFailed = "flow_failed"
        case flowSucceeded = "flow_succeeded"
    }

    enum CaptureSource: String, Sendable {
        case camera
        case photoLibrary = "photo_library"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aifamilygroup.reminder",
        category: "AIPhotoTask"
    )

    nonisolated static func step(
        _ step: Step,
        source: CaptureSource? = nil,
        detail: String = "",
        byteCount: Int? = nil,
        path: String? = nil,
        url: String? = nil
    ) {
        var parts: [String] = ["step=\(step.rawValue)"]
        if let source { parts.append("source=\(source.rawValue)") }
        if let byteCount { parts.append("bytes=\(byteCount)") }
        if let path { parts.append("path=\(path)") }
        if let url { parts.append("url=\(url)") }
        if detail.isEmpty == false { parts.append("detail=\(detail)") }
        let message = parts.joined(separator: " ")

        logger.info("\(message, privacy: .public)")
    }

    nonisolated static func failure(
        step: Step,
        error: Error,
        source: CaptureSource? = nil,
        detail: String = ""
    ) {
        var parts: [String] = ["step=\(step.rawValue)", "error=\(error.localizedDescription)"]
        if let source { parts.append("source=\(source.rawValue)") }
        if detail.isEmpty == false { parts.append("detail=\(detail)") }
        let message = parts.joined(separator: " ")

        logger.error("\(message, privacy: .public)")
        AnalyticsManager.log(
            event: .aiPhotoTaskFailed(
                step: step.rawValue,
                message: analyticsErrorCode(for: error),
                detail: analyticsDetail(step: step, detail: detail)
            )
        )
    }

    /// 供 Firebase 使用的短错误码（避免 ACS013000 参数超长）。
    nonisolated static func analyticsErrorCode(for error: Error) -> String {
        #if canImport(Supabase)
        if let storageError = error as? StorageError {
            if storageError.statusCode == "403"
                || storageError.message.localizedCaseInsensitiveContains("row-level security") {
                return "storage_rls_403"
            }
            if let code = storageError.statusCode {
                return "storage_http_\(code)"
            }
        }
        if let functionsError = error as? FunctionsError {
            if case .httpError(let code, _) = functionsError {
                return "edge_function_http_\(code)"
            }
            return "edge_function_error"
        }
        #endif
        if let parserError = error as? AITaskParserError {
            switch parserError {
            case .uploadFailed(_, let isStorageRLS) where isStorageRLS:
                return "storage_rls_403"
            case .notAuthenticated:
                return "auth_required"
            default:
                return "ai_task_parser_error"
            }
        }
        return "unknown_error"
    }

    private nonisolated static func analyticsDetail(step: Step, detail: String) -> String {
        if detail.isEmpty {
            return step.rawValue
        }
        return "\(step.rawValue):\(detail)"
    }

    /// 将 Supabase Storage 等底层错误展开为可读字符串（仅 Console 日志，不上报 Firebase 全文）。
    nonisolated static func describe(_ error: Error) -> String {
        let mirror = String(describing: error)
        if mirror != error.localizedDescription {
            return "\(error.localizedDescription) | \(mirror)"
        }
        return error.localizedDescription
    }

    struct OcrExtractDebugLog: Sendable {
        var stage: String?
        var timestamp: String?
        var model: String?
        var charCount: Int?
        var lineCount: Int?
        var lines: [String]?
        var text: String?
    }

    nonisolated static func logOcrExtract(_ ocr: OcrExtractDebugLog) {
        var payload: [String: Any] = [
            "stage": ocr.stage ?? "ocr_extract",
            "char_count": ocr.charCount ?? 0,
            "line_count": ocr.lineCount ?? 0,
        ]
        if let model = ocr.model { payload["model"] = model }
        if let timestamp = ocr.timestamp { payload["timestamp"] = timestamp }
        if let lines = ocr.lines { payload["lines"] = lines }
        if let text = ocr.text { payload["text"] = text }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let json = String(data: data, encoding: .utf8) else {
            step(.ocrExtractLogged, detail: ocr.text ?? "")
            return
        }

        logger.info("[AIPhotoTask] ocr_extract_result\n\(json, privacy: .public)")
        step(.ocrExtractLogged, detail: "chars=\(ocr.charCount ?? 0) lines=\(ocr.lineCount ?? 0)")
    }
}
