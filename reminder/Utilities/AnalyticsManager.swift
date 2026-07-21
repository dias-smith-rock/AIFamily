import Foundation

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

#if canImport(Supabase)
import Supabase
#endif

/// 集中管理 Firebase Analytics 埋点；事件命名遵循「群组 (Group)」产品线规范。
enum AnalyticsManager {
    /// 核心转化漏斗事件（snake_case 与 Firebase 控制台一致）。
    enum AppEvent {
        case appOpened
        case signUpCompleted
        case loginCompleted
        case groupCreated(groupId: UUID, isPremium: Bool)
        case groupJoined(groupId: UUID?)
        case virtualMemberAdded(profileId: UUID, groupId: UUID)
        case taskCreated(hasAttachment: Bool)
        case taskCompleted(taskId: UUID)
        case vipPageViewed
        case vipClaimed
        case vipPurchased(plan: String)
        case aiPhotoTaskFailed(step: String, message: String, detail: String)
        case aiPhotoTaskSucceeded
        case guestStarted
        case guestMigrated(taskCount: Int)
        case ledgerCategoryDeleteFailed(step: String, errorCode: String, detail: String)
        case ledgerCategoryDeleteSucceeded
        case ledgerCategoryDeleteBlocked(reason: String)
    }

    /// 新用户判定窗口：Auth 用户创建时间在此时长内视为「注册完成」。
    private static let newRegistrationWindow: TimeInterval = 120

    /// Firebase Analytics 字符串参数上限（见 ACS013000）。
    private static let firebaseMaxParameterLength = 100

    static func log(event: AppEvent) {
        #if canImport(FirebaseAnalytics)
        let (name, parameters) = firebasePayload(for: event)
        Analytics.logEvent(name, parameters: sanitizedFirebaseParameters(parameters))
        #endif
        #if DEBUG
        print("[Analytics] \(debugDescription(for: event))")
        #endif
    }

    /// 在 OAuth / 登录会话建立成功后调用：依据 `auth.users.created_at` 区分注册与登录。
    static func logAuthSessionSucceeded() {
        #if canImport(Supabase)
        Task { @MainActor in
            await logAuthSessionSucceededFromCurrentSession()
        }
        #endif
    }

    @MainActor
    private static func logAuthSessionSucceededFromCurrentSession() async {
        #if canImport(Supabase)
        do {
            let user = try await SupabaseManager.shared.client.auth.session.user
            if isLikelyNewRegistration(createdAt: user.createdAt) {
                log(event: .signUpCompleted)
            } else {
                log(event: .loginCompleted)
            }
        } catch {
            log(event: .loginCompleted)
        }
        #endif
    }

    private static func isLikelyNewRegistration(createdAt: Date) -> Bool {
        Date().timeIntervalSince(createdAt) < newRegistrationWindow
    }

    #if canImport(FirebaseAnalytics)
    private static func firebasePayload(for event: AppEvent) -> (String, [String: Any]?) {
        switch event {
        case .appOpened:
            return ("app_opened", nil)

        case .signUpCompleted:
            return ("sign_up_completed", nil)

        case .loginCompleted:
            return ("login_completed", nil)

        case .groupCreated(let groupId, let isPremium):
            return (
                "group_created",
                [
                    "group_id": groupId.uuidString.lowercased(),
                    "is_premium": isPremium ? 1 : 0,
                ]
            )

        case .groupJoined(let groupId):
            var params: [String: Any] = [:]
            if let groupId {
                params["group_id"] = groupId.uuidString.lowercased()
            }
            return ("group_joined", params.isEmpty ? nil : params)

        case .virtualMemberAdded(let profileId, let groupId):
            return (
                "virtual_member_added",
                [
                    "profile_id": profileId.uuidString.lowercased(),
                    "group_id": groupId.uuidString.lowercased(),
                ]
            )

        case .taskCreated(let hasAttachment):
            return (
                "task_created",
                ["has_attachment": hasAttachment ? 1 : 0]
            )

        case .taskCompleted(let taskId):
            return (
                "task_completed",
                ["task_id": taskId.uuidString.lowercased()]
            )

        case .vipPageViewed:
            return ("vip_page_viewed", nil)

        case .vipClaimed:
            return ("vip_claimed", nil)

        case .vipPurchased(let plan):
            return ("vip_purchased", ["plan": plan])

        case .aiPhotoTaskFailed(let step, let message, let detail):
            return (
                "ai_photo_task_failed",
                [
                    "step": step,
                    "error_code": message,
                    "detail": detail,
                ]
            )

        case .aiPhotoTaskSucceeded:
            return ("ai_photo_task_succeeded", nil)

        case .guestStarted:
            return ("guest_started", nil)

        case .guestMigrated(let taskCount):
            return (
                "guest_migrated",
                ["task_count": taskCount]
            )

        case .ledgerCategoryDeleteFailed(let step, let errorCode, let detail):
            return (
                "ledger_category_delete_failed",
                [
                    "step": step,
                    "error_code": errorCode,
                    "detail": detail,
                ]
            )

        case .ledgerCategoryDeleteSucceeded:
            return ("ledger_category_delete_succeeded", nil)

        case .ledgerCategoryDeleteBlocked(let reason):
            return (
                "ledger_category_delete_blocked",
                ["reason": reason]
            )
        }
    }

    private static func sanitizedFirebaseParameters(_ parameters: [String: Any]?) -> [String: Any]? {
        guard let parameters else { return nil }
        var sanitized: [String: Any] = [:]
        sanitized.reserveCapacity(parameters.count)
        for (key, value) in parameters {
            switch value {
            case let string as String:
                sanitized[key] = String(string.prefix(firebaseMaxParameterLength))
            default:
                sanitized[key] = value
            }
        }
        return sanitized
    }
    #endif

    private static func debugDescription(for event: AppEvent) -> String {
        switch event {
        case .appOpened:
            return "app_opened"
        case .signUpCompleted:
            return "sign_up_completed"
        case .loginCompleted:
            return "login_completed"
        case .groupCreated(let groupId, let isPremium):
            return "group_created group_id=\(groupId.uuidString) is_premium=\(isPremium)"
        case .groupJoined(let groupId):
            return "group_joined group_id=\(groupId?.uuidString ?? "nil")"
        case .virtualMemberAdded(let profileId, let groupId):
            return "virtual_member_added profile_id=\(profileId.uuidString) group_id=\(groupId.uuidString)"
        case .taskCreated(let hasAttachment):
            return "task_created has_attachment=\(hasAttachment)"
        case .taskCompleted(let taskId):
            return "task_completed task_id=\(taskId.uuidString)"
        case .vipPageViewed:
            return "vip_page_viewed"
        case .vipClaimed:
            return "vip_claimed"
        case .vipPurchased(let plan):
            return "vip_purchased plan=\(plan)"
        case .aiPhotoTaskFailed(let step, let message, let detail):
            return "ai_photo_task_failed step=\(step) error=\(message) \(detail)"
        case .aiPhotoTaskSucceeded:
            return "ai_photo_task_succeeded"
        case .guestStarted:
            return "guest_started"
        case .guestMigrated(let taskCount):
            return "guest_migrated task_count=\(taskCount)"
        case .ledgerCategoryDeleteFailed(let step, let errorCode, let detail):
            return "ledger_category_delete_failed step=\(step) error=\(errorCode) \(detail)"
        case .ledgerCategoryDeleteSucceeded:
            return "ledger_category_delete_succeeded"
        case .ledgerCategoryDeleteBlocked(let reason):
            return "ledger_category_delete_blocked reason=\(reason)"
        }
    }
}
