import Foundation

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

#if canImport(Supabase)
import Supabase
#endif

/// 集中管理 Firebase Analytics 埋点；事件命名遵循「群组 (Group)」产品线规范。
/// 核心漏斗（北极星 W1 Active Household）：first_open → group → invite → second_member → task → meaningful_session。
enum AnalyticsManager {
    /// 核心转化漏斗事件（snake_case 与 Firebase 控制台一致）。
    enum AppEvent {
        case appOpened
        case firstOpen(isGuest: Bool)
        case coreSession(dayN: Int, isGuest: Bool)
        case onboardingStep(step: String)
        case activationMilestone(step: String, householdId: UUID?)
        case tabSelected(tab: String)
        case inviteShared(channel: String, householdId: UUID?)
        case inviteAccepted(householdId: UUID?, hoursSinceGroupCreated: Int?)
        case emptyStateCTATapped(surface: String, cta: String)
        case meaningfulSession(action: String, householdId: UUID?)
        case signUpCompleted
        case loginCompleted
        case groupCreated(groupId: UUID, isPremium: Bool)
        case groupJoined(groupId: UUID?)
        case virtualMemberAdded(profileId: UUID, groupId: UUID)
        case taskCreated(hasAttachment: Bool, householdId: UUID?, taskType: String)
        case taskCompleted(taskId: UUID, householdId: UUID?, taskType: String)
        case taskEdited(taskId: UUID, householdId: UUID?, taskType: String)
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
        case ledgerWalletLoad(step: String, detail: String)
        case ledgerPresetL10n(step: String, detail: String)
    }

    enum OnboardingStep {
        static let createGroup = "create_group"
        static let joinGroup = "join_group"
        static let pending = "pending"
        static let enteredMain = "entered_main"
    }

    enum ActivationStep {
        static let firstOpen = "first_open"
        static let groupCreated = "group_created"
        static let enteredMain = "entered_main"
        static let inviteSent = "invite_sent"
        static let inviteAccepted = "invite_accepted"
        static let secondMember = "second_member"
        static let firstTaskCreated = "first_task_created"
        static let firstTaskCompleted = "first_task_completed"
    }

    enum InviteChannel {
        static let link = "link"
        static let qr = "qr"
        static let copy = "copy"
    }

    enum EmptyStateSurface {
        static let schedule = "schedule"
        static let todo = "todo"
        static let family = "family"
    }

    enum EmptyStateCTA {
        static let create = "create"
        static let invite = "invite"
    }

    enum MeaningfulAction {
        static let create = "create"
        static let complete = "complete"
        static let edit = "edit"
    }

    enum TaskTypeParam {
        static let scheduled = "scheduled"
        static let flexible = "flexible"
        static let unknown = "unknown"
    }

    enum TabName {
        static let schedule = "schedule"
        static let todos = "todos"
        static let expenses = "expenses"
        static let location = "location"
        static let settings = "settings"
    }

    /// 新用户判定窗口：Auth 用户创建时间在此时长内视为「注册完成」。
    private static let newRegistrationWindow: TimeInterval = 120

    /// Firebase Analytics 字符串参数上限（见 ACS013000）。
    private static let firebaseMaxParameterLength = 100

    private static let firstOpenDefaultsKey = "analytics.has_logged_first_open"
    private static let firstOpenDateDefaultsKey = "analytics.first_open_date"
    private static let enteredMainDefaultsKey = "analytics.has_logged_onboarding_entered_main"
    private static let meaningfulSessionDayKey = "analytics.meaningful_session.day"
    private static let coreSessionDayKey = "analytics.core_session.day"
    private static let activationPrefix = "analytics.activation."
    private static let hadSecondMemberKey = "analytics.had_second_member"

    static func log(event: AppEvent) {
        emit(event)

        switch event {
        case .taskCreated(_, let householdId, _):
            noteMeaningfulSession(action: MeaningfulAction.create, householdId: householdId)
            logActivationMilestoneIfNeeded(ActivationStep.firstTaskCreated, householdId: householdId)
        case .taskCompleted(_, let householdId, _):
            noteMeaningfulSession(action: MeaningfulAction.complete, householdId: householdId)
            logActivationMilestoneIfNeeded(ActivationStep.firstTaskCompleted, householdId: householdId)
        case .taskEdited(_, let householdId, _):
            noteMeaningfulSession(action: MeaningfulAction.edit, householdId: householdId)
        case .groupCreated(let groupId, _):
            logActivationMilestoneIfNeeded(ActivationStep.groupCreated, householdId: groupId)
        case .inviteShared(_, let householdId):
            logActivationMilestoneIfNeeded(ActivationStep.inviteSent, householdId: householdId)
        case .inviteAccepted(let householdId, _):
            logActivationMilestoneIfNeeded(ActivationStep.inviteAccepted, householdId: householdId)
        default:
            break
        }
    }

    /// 仅上报，不触发派生事件（避免嵌套）。
    private static func emit(_ event: AppEvent) {
        #if canImport(FirebaseAnalytics)
        let (name, parameters) = firebasePayload(for: event)
        Analytics.logEvent(name, parameters: sanitizedFirebaseParameters(parameters))
        #endif
        #if DEBUG
        print("[Analytics] \(debugDescription(for: event))")
        #endif
    }

    // MARK: - Core funnel helpers

    /// 安装后首次打开（含游客）；幂等。
    static func logFirstOpenIfNeeded(isGuest: Bool) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: firstOpenDefaultsKey) == false else { return }
        defaults.set(true, forKey: firstOpenDefaultsKey)
        defaults.set(Date().timeIntervalSince1970, forKey: firstOpenDateDefaultsKey)
        log(event: .firstOpen(isGuest: isGuest))
        setUserProperty(isGuest ? "1" : "0", forName: "is_guest")
        logActivationMilestoneIfNeeded(ActivationStep.firstOpen, householdId: nil)
    }

    /// 每次冷/热启动会话：按自然日记一次 `core_session`，并写 `day_n` user property。
    static func logCoreSessionIfNeeded(isGuest: Bool) {
        let day = currentDayStamp()
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: coreSessionDayKey) != day else {
            refreshDayNUserProperty()
            return
        }
        defaults.set(day, forKey: coreSessionDayKey)
        let dayN = daysSinceFirstOpen()
        refreshDayNUserProperty(explicitDayN: dayN)
        emit(.coreSession(dayN: dayN, isGuest: isGuest))
    }

    /// 组织路由关键步。`entered_main` 终身只记一次。
    static func logOnboardingStep(_ step: String) {
        if step == OnboardingStep.enteredMain {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: enteredMainDefaultsKey) == false else { return }
            defaults.set(true, forKey: enteredMainDefaultsKey)
            logActivationMilestoneIfNeeded(ActivationStep.enteredMain, householdId: nil)
        }
        log(event: .onboardingStep(step: step))
    }

    static func logActivationMilestoneIfNeeded(_ step: String, householdId: UUID?) {
        let key = activationPrefix + step
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: key) == false else { return }
        defaults.set(true, forKey: key)
        emit(.activationMilestone(step: step, householdId: householdId))
    }

    static func logTabSelected(_ tab: String) {
        emit(.tabSelected(tab: tab))
    }

    static func logInviteShared(channel: String, householdId: UUID?) {
        log(event: .inviteShared(channel: channel, householdId: householdId))
    }

    static func logInviteAccepted(householdId: UUID?, hoursSinceGroupCreated: Int? = nil) {
        log(event: .inviteAccepted(householdId: householdId, hoursSinceGroupCreated: hoursSinceGroupCreated))
    }

    static func logEmptyStateCTATapped(surface: String, cta: String) {
        log(event: .emptyStateCTATapped(surface: surface, cta: cta))
    }

    static func logTaskCreated(hasAttachment: Bool, householdId: UUID?, taskType: String) {
        log(event: .taskCreated(hasAttachment: hasAttachment, householdId: householdId, taskType: taskType))
    }

    static func logTaskCompleted(taskId: UUID, householdId: UUID?, taskType: String) {
        log(event: .taskCompleted(taskId: taskId, householdId: householdId, taskType: taskType))
    }

    static func logTaskEdited(taskId: UUID, householdId: UUID?, taskType: String) {
        log(event: .taskEdited(taskId: taskId, householdId: householdId, taskType: taskType))
    }

    static func analyticsTaskType(for task: FamilyTask) -> String {
        switch task.resolvedTaskType {
        case .flexible: TaskTypeParam.flexible
        case .scheduled: TaskTypeParam.scheduled
        case .expense, .income: task.resolvedTaskType.rawValue
        }
    }

    static func analyticsTaskType(isFlexible: Bool) -> String {
        isFlexible ? TaskTypeParam.flexible : TaskTypeParam.scheduled
    }

    /// 当日首次任务 create/complete/edit 记一次 meaningful_session。
    static func noteMeaningfulSession(action: String, householdId: UUID?) {
        let day = Self.currentDayStamp()
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: meaningfulSessionDayKey) != day else { return }
        defaults.set(day, forKey: meaningfulSessionDayKey)
        emit(.meaningfulSession(action: action, householdId: householdId))
    }

    static func updateGuestUserProperty(isGuest: Bool) {
        setUserProperty(isGuest ? "1" : "0", forName: "is_guest")
    }

    static func updateHouseholdMemberUserProperties(activeHumanCount: Int) {
        let hasSecond = activeHumanCount >= 2
        setUserProperty(hasSecond ? "1" : "0", forName: "has_second_member")
        let bucket: String
        switch activeHumanCount {
        case ...0: bucket = "0"
        case 1: bucket = "1"
        case 2: bucket = "2"
        case 3...5: bucket = "3_5"
        default: bucket = "6_plus"
        }
        setUserProperty(bucket, forName: "member_count_bucket")

        let defaults = UserDefaults.standard
        let previouslyHadSecond = defaults.bool(forKey: hadSecondMemberKey)
        if hasSecond, previouslyHadSecond == false {
            defaults.set(true, forKey: hadSecondMemberKey)
            logActivationMilestoneIfNeeded(ActivationStep.secondMember, householdId: nil)
        }
    }

    // MARK: - Auth session

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

    private static func daysSinceFirstOpen() -> Int {
        let defaults = UserDefaults.standard
        let ts = defaults.double(forKey: firstOpenDateDefaultsKey)
        guard ts > 0 else { return 0 }
        let first = Date(timeIntervalSince1970: ts)
        let startFirst = Calendar.current.startOfDay(for: first)
        let startToday = Calendar.current.startOfDay(for: Date())
        let days = Calendar.current.dateComponents([.day], from: startFirst, to: startToday).day ?? 0
        return max(0, days)
    }

    private static func refreshDayNUserProperty(explicitDayN: Int? = nil) {
        let dayN = explicitDayN ?? daysSinceFirstOpen()
        setUserProperty(String(dayN), forName: "day_n")
    }

    private static func currentDayStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func setUserProperty(_ value: String?, forName name: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.setUserProperty(value, forName: name)
        #endif
    }

    #if canImport(FirebaseAnalytics)
    private static func firebasePayload(for event: AppEvent) -> (String, [String: Any]?) {
        switch event {
        case .appOpened:
            return ("app_opened", nil)

        case .firstOpen(let isGuest):
            return ("first_open", ["is_guest": isGuest ? 1 : 0])

        case .coreSession(let dayN, let isGuest):
            return (
                "core_session",
                [
                    "day_n": dayN,
                    "is_guest": isGuest ? 1 : 0,
                ]
            )

        case .onboardingStep(let step):
            return ("onboarding_step", ["step": step])

        case .activationMilestone(let step, let householdId):
            var params: [String: Any] = ["step": step]
            if let householdId {
                params["household_id"] = householdId.uuidString.lowercased()
            }
            return ("activation_milestone", params)

        case .tabSelected(let tab):
            return ("tab_selected", ["tab": tab])

        case .inviteShared(let channel, let householdId):
            var params: [String: Any] = ["channel": channel]
            if let householdId {
                params["household_id"] = householdId.uuidString.lowercased()
            }
            return ("invite_shared", params)

        case .inviteAccepted(let householdId, let hoursSinceGroupCreated):
            var params: [String: Any] = [:]
            if let householdId {
                params["household_id"] = householdId.uuidString.lowercased()
            }
            if let hoursSinceGroupCreated {
                params["hours_since_group_created"] = hoursSinceGroupCreated
            }
            return ("invite_accepted", params.isEmpty ? nil : params)

        case .emptyStateCTATapped(let surface, let cta):
            return (
                "empty_state_cta_tapped",
                [
                    "surface": surface,
                    "cta": cta,
                ]
            )

        case .meaningfulSession(let action, let householdId):
            var params: [String: Any] = ["action": action]
            if let householdId {
                params["household_id"] = householdId.uuidString.lowercased()
            }
            return ("meaningful_session", params)

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

        case .taskCreated(let hasAttachment, let householdId, let taskType):
            var params: [String: Any] = [
                "has_attachment": hasAttachment ? 1 : 0,
                "task_type": taskType,
            ]
            if let householdId {
                params["household_id"] = householdId.uuidString.lowercased()
            }
            return ("task_created", params)

        case .taskCompleted(let taskId, let householdId, let taskType):
            var params: [String: Any] = [
                "task_id": taskId.uuidString.lowercased(),
                "task_type": taskType,
            ]
            if let householdId {
                params["household_id"] = householdId.uuidString.lowercased()
            }
            return ("task_completed", params)

        case .taskEdited(let taskId, let householdId, let taskType):
            var params: [String: Any] = [
                "task_id": taskId.uuidString.lowercased(),
                "task_type": taskType,
            ]
            if let householdId {
                params["household_id"] = householdId.uuidString.lowercased()
            }
            return ("task_edited", params)

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

        case .ledgerWalletLoad(let step, let detail):
            return (
                "ledger_wallet_load",
                [
                    "step": step,
                    "detail": detail,
                ]
            )

        case .ledgerPresetL10n(let step, let detail):
            return (
                "ledger_preset_l10n",
                [
                    "step": step,
                    "detail": detail,
                ]
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
        case .firstOpen(let isGuest):
            return "first_open is_guest=\(isGuest)"
        case .coreSession(let dayN, let isGuest):
            return "core_session day_n=\(dayN) is_guest=\(isGuest)"
        case .onboardingStep(let step):
            return "onboarding_step step=\(step)"
        case .activationMilestone(let step, let householdId):
            return "activation_milestone step=\(step) household_id=\(householdId?.uuidString ?? "nil")"
        case .tabSelected(let tab):
            return "tab_selected tab=\(tab)"
        case .inviteShared(let channel, let householdId):
            return "invite_shared channel=\(channel) household_id=\(householdId?.uuidString ?? "nil")"
        case .inviteAccepted(let householdId, let hours):
            return "invite_accepted household_id=\(householdId?.uuidString ?? "nil") hours=\(hours.map(String.init) ?? "nil")"
        case .emptyStateCTATapped(let surface, let cta):
            return "empty_state_cta_tapped surface=\(surface) cta=\(cta)"
        case .meaningfulSession(let action, let householdId):
            return "meaningful_session action=\(action) household_id=\(householdId?.uuidString ?? "nil")"
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
        case .taskCreated(let hasAttachment, let householdId, let taskType):
            return "task_created has_attachment=\(hasAttachment) task_type=\(taskType) household_id=\(householdId?.uuidString ?? "nil")"
        case .taskCompleted(let taskId, let householdId, let taskType):
            return "task_completed task_id=\(taskId.uuidString) task_type=\(taskType) household_id=\(householdId?.uuidString ?? "nil")"
        case .taskEdited(let taskId, let householdId, let taskType):
            return "task_edited task_id=\(taskId.uuidString) task_type=\(taskType) household_id=\(householdId?.uuidString ?? "nil")"
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
        case .ledgerWalletLoad(let step, let detail):
            return "ledger_wallet_load step=\(step) \(detail)"
        case .ledgerPresetL10n(let step, let detail):
            return "ledger_preset_l10n step=\(step) \(detail)"
        }
    }
}
