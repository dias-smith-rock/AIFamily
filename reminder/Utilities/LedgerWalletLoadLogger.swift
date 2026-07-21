import Foundation
import os

#if canImport(Supabase)
import Supabase
#endif

/// Wallet Tab 加载诊断埋点：Console + os.Logger + Analytics + Crashlytics。
/// 仅观测，不改变加载逻辑。
enum LedgerWalletLoadLogger {
    enum Step: String, Sendable {
        case mainTaskStart = "main_task_start"
        case mainTaskSkipBootstrap = "main_task_skip_bootstrap"
        case mainTaskSkipAccess = "main_task_skip_access"
        case mainTaskEnd = "main_task_end"
        case onChangeHousehold = "on_change_household"
        case onChangeMembership = "on_change_membership"
        case notificationReload = "notification_reload"
        case setHousehold = "set_household"
        case rosterStart = "roster_start"
        case rosterEnd = "roster_end"
        case rosterFail = "roster_fail"
        case rosterCancel = "roster_cancel"
        case ledgerStart = "ledger_start"
        case ledgerCacheHit = "ledger_cache_hit"
        case ensurePresetStart = "ensure_preset_start"
        case ensurePresetOk = "ensure_preset_ok"
        case ensurePresetFail = "ensure_preset_fail"
        case ensurePresetCancel = "ensure_preset_cancel"
        case payloadStart = "payload_start"
        case payloadOk = "payload_ok"
        case payloadFail = "payload_fail"
        case payloadCancel = "payload_cancel"
        case retryNeeded = "retry_needed"
        case ledgerEndEmpty = "ledger_end_empty"
        case ledgerEndOk = "ledger_end_ok"
        case emptyUIShown = "empty_ui_shown"
        case reloadTapped = "reload_tapped"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aifamilygroup.reminder",
        category: "LedgerWalletLoad"
    )

    nonisolated(unsafe) private(set) static var lastSummary: String = ""
    nonisolated(unsafe) private static var sequence: Int = 0

    /// 分配一次加载链路 token，便于对照并发/取消。
    nonisolated static func nextToken() -> Int {
        sequence += 1
        return sequence
    }

    nonisolated static func step(
        _ step: Step,
        token: Int? = nil,
        source: String = "",
        householdId: UUID? = nil,
        detail: String = ""
    ) {
        var parts: [String] = ["[LedgerWalletLoad]", "step=\(step.rawValue)"]
        if let token { parts.append("token=\(token)") }
        if source.isEmpty == false { parts.append("source=\(source)") }
        if let householdId { parts.append("household_id=\(householdId.uuidString.lowercased())") }
        if detail.isEmpty == false { parts.append("detail=\(detail)") }
        let message = parts.joined(separator: " ")
        lastSummary = message
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print(message)
        #endif
        CrashReporting.log(message)

        // 关键结果 / 取消 / 空态 / 失败 上报 Analytics，便于线上聚合。
        switch step {
        case .ledgerEndEmpty, .ledgerEndOk, .ledgerCacheHit,
             .rosterCancel, .ensurePresetCancel, .payloadCancel,
             .rosterFail, .ensurePresetFail, .payloadFail,
             .emptyUIShown, .mainTaskSkipBootstrap, .mainTaskSkipAccess:
            AnalyticsManager.log(
                event: .ledgerWalletLoad(
                    step: step.rawValue,
                    detail: String((detail.isEmpty ? source : detail).prefix(100))
                )
            )
        default:
            break
        }
    }

    nonisolated static func failure(
        step: Step,
        error: Error,
        token: Int? = nil,
        source: String = "",
        householdId: UUID? = nil,
        detail: String = ""
    ) {
        let code = errorCode(for: error)
        let dump = errorDump(error)
        var parts: [String] = [
            "[LedgerWalletLoad]",
            "step=\(step.rawValue)",
            "error_code=\(code)",
            "error=\(error.localizedDescription)",
            "dump=\(dump)",
        ]
        if let token { parts.append("token=\(token)") }
        if source.isEmpty == false { parts.append("source=\(source)") }
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
                "ledger_wallet_step": step.rawValue,
                "ledger_wallet_error_code": code,
                "ledger_wallet_token": token.map(String.init) ?? "",
                "ledger_household_id": householdId?.uuidString.lowercased() ?? "",
                "ledger_detail": String(detail.prefix(100)),
            ]
        )
        AnalyticsManager.log(
            event: .ledgerWalletLoad(
                step: step.rawValue,
                detail: String("\(code)|\(detail.isEmpty ? dump : detail)".prefix(100))
            )
        )
    }

    nonisolated static func errorCode(for error: Error) -> String {
        if error is CancellationError { return "cancellation" }
        #if canImport(Supabase)
        if let db = error as? PostgrestError {
            if let code = db.code, code.isEmpty == false {
                return "postgrest_\(code)"
            }
            return "postgrest_error"
        }
        #endif
        if error is DecodingError { return "decoding_error" }
        if let url = error as? URLError { return "url_\(url.code.rawValue)" }
        return "unknown"
    }

    nonisolated static func errorDump(_ error: Error) -> String {
        #if canImport(Supabase)
        if let db = error as? PostgrestError {
            return "PostgrestError(code=\(db.code ?? "nil"), message=\(db.message))"
        }
        #endif
        return String(describing: error)
    }

    nonisolated static func categoryCounts(
        expense: Int,
        income: Int,
        tags: Int,
        transactions: Int
    ) -> String {
        "expense=\(expense) income=\(income) tags=\(tags) tx=\(transactions)"
    }
}
