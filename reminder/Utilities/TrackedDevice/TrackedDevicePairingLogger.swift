import Foundation
import os

#if canImport(Supabase)
import Supabase
#endif

/// 儿童设备配对诊断埋点：Xcode Console + os.Logger + Crashlytics。仅观测，不改变配对逻辑。
enum TrackedDevicePairingLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aifamilygroup.reminder",
        category: "TrackedDevicePairing"
    )

    nonisolated(unsafe) private(set) static var lastMessage: String = ""

    nonisolated static func event(
        _ name: String,
        code: String = "",
        userId: UUID? = nil,
        detail: String = ""
    ) {
        var parts = ["[TrackedPairing]", "event=\(name)"]
        if code.isEmpty == false {
            parts.append("code=\(code)")
        }
        if let userId {
            parts.append("user_id=\(userId.uuidString.lowercased())")
        }
        if detail.isEmpty == false {
            parts.append("detail=\(detail)")
        }
        emit(parts.joined(separator: " "))
    }

    nonisolated static func failure(_ error: Error, stage: String, code: String = "") {
        let dump = errorDump(error)
        event("fail", code: code, detail: "stage=\(stage) dump=\(dump)")
        CrashReporting.record(error, context: [
            "tracked_pairing_stage": stage,
            "tracked_pairing_dump": dump,
        ])
    }

    nonisolated static func errorDump(_ error: Error) -> String {
        #if canImport(Supabase)
        if let db = error as? PostgrestError {
            return "PostgrestError(code=\(db.code ?? "nil"), message=\(db.message), detail=\(db.detail ?? "nil"), hint=\(db.hint ?? "nil"))"
        }
        #endif
        if let pairing = error as? TrackedDevicePairingError {
            return "TrackedDevicePairingError(\(pairing.localizedDescription ?? String(describing: pairing)))"
        }
        return "\(String(describing: error)) | localized=\(error.localizedDescription)"
    }

    /// 给 UI 展示：业务文案 + 原始库错误，便于对照 nickname / RPC 名。
    nonisolated static func userFacingMessage(_ error: Error) -> String {
        let dump = errorDump(error)
        lastMessage = dump
        let localized = error.localizedDescription
        if localized.isEmpty {
            return dump
        }
        if dump.contains(localized) {
            return dump
        }
        return "\(localized)\n\(dump)"
    }

    private nonisolated static func emit(_ message: String) {
        lastMessage = message
        logger.info("\(message, privacy: .public)")
        print(message)
        CrashReporting.log(message)
    }
}
