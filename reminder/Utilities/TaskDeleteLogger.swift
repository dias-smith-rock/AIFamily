import Foundation
import os

#if canImport(Supabase)
import Supabase
#endif

/// 日程 / 待办「删除任务」诊断埋点：Console + os.Logger + Analytics + Crashlytics。
enum TaskDeleteLogger {
    enum Source: String, Sendable {
        case editForm = "edit_form"
        case contextMenu = "context_menu"
        case taskDetail = "task_detail"
        case stickyDrop = "sticky_drop"
        case stickyMenu = "sticky_menu"
        case todoList = "todo_list"
        case unknown = "unknown"
    }

    enum Step: String, Sendable {
        case tapDelete = "tap_delete"
        case confirmPresented = "confirm_presented"
        case confirmAccepted = "confirm_accepted"
        case confirmCancelled = "confirm_cancelled"
        case permissionBlocked = "permission_blocked"
        case begin = "begin"
        case networkCheck = "network_check"
        case serviceStarted = "service_started"
        case remoteReturned = "remote_returned"
        case remoteEmpty = "remote_empty"
        case localCacheUpdated = "local_cache_updated"
        case uiDismiss = "ui_dismiss"
        case succeeded = "succeeded"
        case failed = "failed"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aifamilygroup.reminder",
        category: "TaskDelete"
    )

    /// 最近一次删除诊断摘要（便于 Debug 对照）。
    nonisolated(unsafe) private(set) static var lastSummary: String = ""

    nonisolated static func step(
        _ step: Step,
        source: Source = .unknown,
        taskId: UUID? = nil,
        householdId: UUID? = nil,
        scope: String? = nil,
        membershipId: UUID? = nil,
        isCreator: Bool? = nil,
        allowsEditing: Bool? = nil,
        detail: String = ""
    ) {
        var parts: [String] = [
            "[TaskDelete]",
            "step=\(step.rawValue)",
            "source=\(source.rawValue)",
        ]
        if let taskId { parts.append("task_id=\(taskId.uuidString.lowercased())") }
        if let householdId { parts.append("household_id=\(householdId.uuidString.lowercased())") }
        if let scope { parts.append("scope=\(scope)") }
        if let membershipId { parts.append("membership_id=\(membershipId.uuidString.lowercased())") }
        if let isCreator { parts.append("is_creator=\(isCreator)") }
        if let allowsEditing { parts.append("allows_editing=\(allowsEditing)") }
        if detail.isEmpty == false { parts.append("detail=\(detail)") }
        let message = parts.joined(separator: " ")
        lastSummary = message
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print(message)
        #endif
        CrashReporting.log(message)

        AnalyticsManager.log(
            event: .taskDeleteStep(
                step: step.rawValue,
                source: source.rawValue,
                detail: String(detail.prefix(100))
            )
        )
    }

    nonisolated static func failure(
        step: Step,
        error: Error,
        source: Source = .unknown,
        taskId: UUID? = nil,
        householdId: UUID? = nil,
        scope: String? = nil,
        detail: String = ""
    ) {
        let code = analyticsErrorCode(for: error)
        let dump = errorDump(error)
        var parts: [String] = [
            "[TaskDelete]",
            "step=\(step.rawValue)",
            "source=\(source.rawValue)",
            "error_code=\(code)",
            "error=\(error.localizedDescription)",
            "dump=\(dump)",
        ]
        if let taskId { parts.append("task_id=\(taskId.uuidString.lowercased())") }
        if let householdId { parts.append("household_id=\(householdId.uuidString.lowercased())") }
        if let scope { parts.append("scope=\(scope)") }
        if detail.isEmpty == false { parts.append("detail=\(detail)") }
        let message = parts.joined(separator: " ")
        lastSummary = message
        logger.error("\(message, privacy: .public)")
        #if DEBUG
        print(message)
        #endif

        CrashReporting.record(
            error,
            context: [
                "task_delete_step": step.rawValue,
                "task_delete_source": source.rawValue,
                "task_delete_error_code": code,
                "task_id": taskId?.uuidString.lowercased() ?? "",
                "household_id": householdId?.uuidString.lowercased() ?? "",
                "task_delete_detail": String(detail.prefix(100)),
            ]
        )
        AnalyticsManager.log(
            event: .taskDeleteFailed(
                step: step.rawValue,
                source: source.rawValue,
                errorCode: code,
                detail: String((detail.isEmpty ? dump : detail).prefix(100))
            )
        )
    }

    nonisolated static func succeeded(
        source: Source,
        taskId: UUID?,
        householdId: UUID?,
        scope: String? = nil,
        detail: String = ""
    ) {
        step(
            .succeeded,
            source: source,
            taskId: taskId,
            householdId: householdId,
            scope: scope,
            detail: detail
        )
        AnalyticsManager.log(
            event: .taskDeleteSucceeded(
                source: source.rawValue,
                taskId: taskId?.uuidString.lowercased() ?? ""
            )
        )
    }

    nonisolated static func analyticsErrorCode(for error: Error) -> String {
        if let service = error as? SupabaseServiceError {
            switch service {
            case .deleteNotPermittedOrMissing: return "delete_not_permitted_or_missing"
            case .sdkUnavailable: return "sdk_unavailable"
            case .invalidConfiguration: return "invalid_configuration"
            case .invalidResponse: return "invalid_response"
            case .unsupportedOperation: return "unsupported_operation"
            }
        }
        if let write = error as? TaskLocalWriteSupport.WriteError {
            switch write {
            case .offline: return "offline"
            case .serviceUnavailable: return "service_unavailable"
            }
        }
        #if canImport(Supabase)
        if let db = error as? PostgrestError {
            if let code = db.code, code.isEmpty == false {
                if code == "PGRST116" { return "postgrest_no_rows" }
                return "postgrest_\(code)"
            }
            let msg = db.message.lowercased()
            if msg.contains("row-level security") || msg.contains("rls") {
                return "postgrest_rls"
            }
            if msg.contains("0 rows") || msg.contains("cannot coerce") {
                return "postgrest_no_rows"
            }
            return "postgrest_error"
        }
        #endif
        if error is DecodingError {
            return "decoding_error"
        }
        if let url = error as? URLError {
            return "url_\(url.code.rawValue)"
        }
        return "unknown"
    }

    nonisolated static func errorDump(_ error: Error) -> String {
        #if canImport(Supabase)
        if let db = error as? PostgrestError {
            return "PostgrestError(code=\(db.code ?? "nil"), message=\(db.message), detail=\(db.detail ?? "nil"), hint=\(db.hint ?? "nil"))"
        }
        #endif
        if let decoding = error as? DecodingError {
            return "DecodingError(\(String(describing: decoding)))"
        }
        return String(describing: error)
    }
}
