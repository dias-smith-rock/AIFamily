import Foundation
import os

#if canImport(Supabase)
import Supabase
#endif

/// 账本「删除分类」诊断埋点：Console + os.Logger + Analytics + Crashlytics。
enum LedgerCategoryDeleteLogger {
    enum Step: String, Sendable {
        case attempt = "attempt"
        case blockedHasTransactions = "blocked_has_transactions"
        case confirmPresented = "confirm_presented"
        case serviceStarted = "service_started"
        case updateReturned = "update_returned"
        case tagsSoftDeleted = "tags_soft_deleted"
        case localStateUpdated = "local_state_updated"
        case succeeded = "succeeded"
        case failed = "failed"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aifamilygroup.reminder",
        category: "LedgerCategoryDelete"
    )

    /// 最近一次删除诊断摘要（便于 Debug 对照）。
    nonisolated(unsafe) private(set) static var lastSummary: String = ""

    nonisolated static func step(
        _ step: Step,
        categoryId: UUID? = nil,
        categoryName: String? = nil,
        householdId: UUID? = nil,
        detail: String = ""
    ) {
        var parts: [String] = ["[LedgerDelete]", "step=\(step.rawValue)"]
        if let categoryId { parts.append("category_id=\(categoryId.uuidString.lowercased())") }
        if let categoryName { parts.append("name=\(categoryName)") }
        if let householdId { parts.append("household_id=\(householdId.uuidString.lowercased())") }
        if detail.isEmpty == false { parts.append("detail=\(detail)") }
        let message = parts.joined(separator: " ")
        lastSummary = message
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print(message)
        #endif
        CrashReporting.log(message)
    }

    nonisolated static func failure(
        step: Step,
        error: Error,
        categoryId: UUID? = nil,
        categoryName: String? = nil,
        householdId: UUID? = nil,
        detail: String = ""
    ) {
        let code = analyticsErrorCode(for: error)
        let dump = errorDump(error)
        var parts: [String] = [
            "[LedgerDelete]",
            "step=\(step.rawValue)",
            "error_code=\(code)",
            "error=\(error.localizedDescription)",
            "dump=\(dump)",
        ]
        if let categoryId { parts.append("category_id=\(categoryId.uuidString.lowercased())") }
        if let categoryName { parts.append("name=\(categoryName)") }
        if let householdId { parts.append("household_id=\(householdId.uuidString.lowercased())") }
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
                "ledger_delete_step": step.rawValue,
                "ledger_delete_error_code": code,
                "ledger_category_id": categoryId?.uuidString.lowercased() ?? "",
                "ledger_household_id": householdId?.uuidString.lowercased() ?? "",
                "ledger_detail": String(detail.prefix(100)),
            ]
        )
        AnalyticsManager.log(
            event: .ledgerCategoryDeleteFailed(
                step: step.rawValue,
                errorCode: code,
                detail: String((detail.isEmpty ? dump : detail).prefix(100))
            )
        )
    }

    nonisolated static func analyticsErrorCode(for error: Error) -> String {
        if let mutation = error as? LedgerCategoryMutationError {
            switch mutation {
            case .hasLinkedTransactions: return "has_linked_transactions"
            case .softDeleteDidNotPersist: return "soft_delete_did_not_persist"
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
