import Foundation
import UserNotifications

/// 本地通知（强提醒）：按 `task.id` 管理 pending identifier，便于精确撤销。
/// 使用 `actor` 串行化对 `UNUserNotificationCenter` 与载荷的处理，避免 `Sendable` 载荷跨执行器时
/// 对 `String` 等字段的并发/边界问题触发 `getSharedUTF8Start` 类崩溃。
actor NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private nonisolated static let idPrefix = "com.aifamily.task."

    private init() {}

    #if DEBUG
    private nonisolated static func debugLog(_ message: String) {
        print("[NotificationManager] \(message)")
    }
    #else
    private nonisolated static func debugLog(_ message: String) {}
    #endif

    /// 请求横幅 / 声音 / 角标权限。
    func requestAuthorization() async -> Bool {
        await requestAuthorizationIfNeeded()
    }

    /// 请求横幅 / 声音 / 角标权限。
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            Self.debugLog("auth already granted status=\(String(describing: settings.authorizationStatus))")
            return true
        default:
            break
        }
        do {
            let ok = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            Self.debugLog("auth request result=\(ok)")
            return ok
        } catch {
            Self.debugLog("auth request error=\(error.localizedDescription)")
            return false
        }
    }

    /// 批量对齐本地通知：复用单任务 `syncTaskAlarms`（`dueDate - reminderOffsets`），最多保留未来最近的 10 个任务。
    func syncLocalNotifications(
        upcomingTasks: [TaskAlarmPayload],
        cancelForTaskIds staleTaskIds: [UUID] = []
    ) async {
        guard await requestAuthorizationIfNeeded() else {
            Self.debugLog("bulk sync abort reason=notification_not_authorized")
            return
        }

        for taskId in staleTaskIds {
            cancelAllPending(for: taskId)
        }

        let top = upcomingTasks.prefix(10)
        for payload in top {
            await syncTaskAlarms(for: payload.detachedCopy())
        }

        Self.debugLog(
            "bulk sync done scheduledTasks=\(top.count) cancelledStale=\(staleTaskIds.count)"
        )
    }

    /// 撤销与该任务相关的所有待触发与已送达本地通知（identifier 统一前缀）。
    func cancelAllPending(for taskId: UUID) {
        let ids = Self.allIdentifiers(forTaskId: taskId)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        Self.debugLog("cancel taskId=\(taskId.uuidString) clearedIdentifiers.count=\(ids.count)")
    }

    /// 进入前台清空桌面角标；不影响后续重新同步/注册本地通知。
    func clearBadgeCount() {
        center.setBadgeCount(0)
    }

    /// 先清空旧请求，再按 DTO 重建闹钟。
    func syncTaskAlarms(for incoming: TaskAlarmPayload) async {
        let payload = incoming.detachedCopy()
        let decision = Self.schedulingDecision(for: payload)
        #if DEBUG
        let offsetsDesc: String
        if let ro = payload.reminderOffsets, ro.isEmpty == false {
            offsetsDesc = ro.map(String.init).joined(separator: ",")
        } else {
            offsetsDesc = "nil"
        }
        let dueTs = payload.dueDate.map { String(format: "%.3f", $0.timeIntervalSince1970) } ?? "nil"
        Self.debugLog(
            "sync begin taskId=\(payload.id.uuidString) isAllDay=\(payload.isAllDay) status=\(payload.status.rawValue) due_ts=\(dueTs) offsets=\(offsetsDesc)"
        )
        #endif

        cancelAllPending(for: payload.id)

        guard decision.allowed else {
            if let reason = decision.skipReason {
                Self.debugLog("sync skip taskId=\(payload.id.uuidString) reason=\(reason)")
            }
            return
        }

        guard await requestAuthorizationIfNeeded() else {
            Self.debugLog("sync abort taskId=\(payload.id.uuidString) reason=notification_not_authorized")
            return
        }

        if payload.isAllDay {
            let n = await scheduleAllDayAlarms(for: payload)
            Self.debugLog("sync done taskId=\(payload.id.uuidString) mode=allDay scheduledRequests=\(n)")
        } else {
            let n = await scheduleTimedAlarms(for: payload)
            Self.debugLog("sync done taskId=\(payload.id.uuidString) mode=timed scheduledRequests=\(n)")
        }
    }

    private nonisolated static func schedulingDecision(for payload: TaskAlarmPayload) -> (allowed: Bool, skipReason: String?) {
        switch payload.status {
        case .completed:
            return (false, "status_completed")
        case .cancelled:
            return (false, "status_cancelled")
        case .failed:
            return (false, "status_failed")
        case .expired:
            return (false, "status_expired")
        default:
            break
        }

        let now = Date()

        if payload.isAllDay == false {
            guard let due = payload.dueDate else { return (false, "timed_missing_dueDate") }
            if due < now { return (false, "timed_dueDate_passed") }
            return (true, nil)
        }

        guard let due = payload.dueDate else { return (false, "allday_missing_dueDate") }
        let cal = Calendar.current
        let startOfDue = cal.startOfDay(for: due)
        let startOfToday = cal.startOfDay(for: now)
        if startOfDue < startOfToday { return (false, "allday_due_day_passed") }
        return (true, nil)
    }

    /// 定时任务：对每个 `reminderOffsets` 在 `dueDate - offset` 触发。返回成功加入系统的请求数。
    @discardableResult
    private func scheduleTimedAlarms(for payload: TaskAlarmPayload) async -> Int {
        guard let offsets = payload.reminderOffsets, offsets.isEmpty == false else {
            Self.debugLog("timed schedule skip taskId=\(payload.id.uuidString) reason=no_reminder_offsets")
            return 0
        }
        guard let anchor = payload.dueDate else {
            Self.debugLog("timed schedule skip taskId=\(payload.id.uuidString) reason=no_dueDate")
            return 0
        }

        let titleForAlert = Self.contentTitle(from: payload.title)

        var scheduled = 0
        var skippedPast = 0
        for (idx, minutes) in offsets.enumerated() where idx < 8 {
            let fireDate = anchor.addingTimeInterval(-Double(minutes * 60))
            guard fireDate > Date() else {
                skippedPast += 1
                continue
            }
            let id = Self.identifier(taskId: payload.id, suffix: "timed-\(idx)")
            let ok = await addRequest(
                identifier: id,
                title: titleForAlert,
                body: Self.timedReminderBody(minutesBefore: minutes),
                at: fireDate,
                taskId: payload.id,
                householdId: payload.householdId,
                householdName: payload.householdDisplayName,
                isFlexibleTodo: payload.isFlexibleTodo
            )
            if ok {
                scheduled += 1
                Self.debugLog("timed add ok id=\(id) fire=\(Self.debugDate(fireDate)) offsetMin=\(minutes)")
            }
        }
        Self.debugLog("timed summary taskId=\(payload.id.uuidString) scheduled=\(scheduled) skippedPastFire=\(skippedPast)")
        return scheduled
    }

    /// 全天任务：在执行日「前一天」的 18:00 与 21:00 各一条。返回成功加入系统的请求数。
    @discardableResult
    private func scheduleAllDayAlarms(for payload: TaskAlarmPayload) async -> Int {
        guard let due = payload.dueDate else {
            Self.debugLog("allday schedule skip taskId=\(payload.id.uuidString) reason=no_dueDate")
            return 0
        }
        let cal = Calendar.current
        let startOfDue = cal.startOfDay(for: due)
        guard let previousDay = cal.date(byAdding: .day, value: -1, to: startOfDue) else {
            Self.debugLog("allday schedule skip taskId=\(payload.id.uuidString) reason=calendar_previousDay_nil")
            return 0
        }

        let ymd = cal.dateComponents([.year, .month, .day], from: previousDay)

        var c18 = DateComponents()
        c18.calendar = cal
        c18.timeZone = cal.timeZone
        c18.year = ymd.year
        c18.month = ymd.month
        c18.day = ymd.day
        c18.hour = 18
        c18.minute = 0
        c18.second = 0

        var c21 = c18
        c21.hour = 21

        guard let fire18 = cal.date(from: c18), let fire21 = cal.date(from: c21) else {
            Self.debugLog("allday schedule skip taskId=\(payload.id.uuidString) reason=calendar_fireDate_nil")
            return 0
        }

        // 不在系统通知正文中拼接用户标题，避免异常 `String` 在插值时崩溃；详情在 App 内查看。
        let baseBody = AppLocalized.localizedSync(L10n.Schedule.anAllDayTaskIsDueOnTheScheduledDateOpe)

        var scheduled = 0
        let now = Date()

        if fire18 > now {
            let id18 = Self.identifier(taskId: payload.id, suffix: "allday-18")
            let ok = await addRequest(
                identifier: id18,
                title: AppLocalized.localizedSync(L10n.Common.allDayTaskReminder),
                body: baseBody,
                at: fire18,
                taskId: payload.id,
                householdId: payload.householdId,
                householdName: payload.householdDisplayName,
                isFlexibleTodo: payload.isFlexibleTodo
            )
            if ok {
                scheduled += 1
                Self.debugLog("allday add ok id=\(id18) fire=\(Self.debugDate(fire18))")
            }
        } else {
            Self.debugLog("allday skip slot=18:00 taskId=\(payload.id.uuidString) reason=fire_in_past fire=\(Self.debugDate(fire18))")
        }

        if fire21 > now {
            let id21 = Self.identifier(taskId: payload.id, suffix: "allday-21")
            let ok = await addRequest(
                identifier: id21,
                title: AppLocalized.localizedSync(L10n.Common.allDayTaskReminder),
                body: baseBody,
                at: fire21,
                taskId: payload.id,
                householdId: payload.householdId,
                householdName: payload.householdDisplayName,
                isFlexibleTodo: payload.isFlexibleTodo
            )
            if ok {
                scheduled += 1
                Self.debugLog("allday add ok id=\(id21) fire=\(Self.debugDate(fire21))")
            }
        } else {
            Self.debugLog("allday skip slot=21:00 taskId=\(payload.id.uuidString) reason=fire_in_past fire=\(Self.debugDate(fire21))")
        }

        Self.debugLog("allday summary taskId=\(payload.id.uuidString) scheduled=\(scheduled) previousDay=\(Self.debugDate(previousDay))")
        return scheduled
    }

    private func addRequest(
        identifier: String,
        title: String,
        body: String,
        at date: Date,
        taskId: UUID,
        householdId: UUID,
        householdName: String?,
        isFlexibleTodo: Bool
    ) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var userInfo: [AnyHashable: Any] = [
            "taskId": taskId.uuidString.lowercased(),
            "householdId": householdId.uuidString.lowercased(),
            "isFlexibleTodo": isFlexibleTodo
        ]
        if let name = householdName?.trimmingCharacters(in: .whitespacesAndNewlines),
           name.isEmpty == false {
            userInfo["householdName"] = name
        }
        content.userInfo = userInfo

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            Self.debugLog("add failed id=\(identifier) error=\(error.localizedDescription)")
            return false
        }
    }

    private nonisolated static func timedReminderBody(minutesBefore: Int) -> String {
        if minutesBefore == 0 {
            return AppLocalized.localizedSync(L10n.Schedule.taskStartingSoon)
        }
        return String(
            format: AppLocalized.localizedSync(L10n.Schedule.lldMinBeforeTaskStartingSoon),
            minutesBefore
        )
    }

    /// 将用户标题截断为通知栏安全长度；异常或空白时退回默认文案。
    private nonisolated static func contentTitle(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return AppLocalized.localizedSync(L10n.Family.groupTask)
        }
        let maxLen = 80
        if trimmed.count <= maxLen {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxLen, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
        return String(trimmed[..<end]) + "…"
    }

    private nonisolated static func identifier(taskId: UUID, suffix: String) -> String {
        "\(idPrefix)\(taskId.uuidString.lowercased()).\(suffix)"
    }

    private nonisolated static func allIdentifiers(forTaskId taskId: UUID) -> [String] {
        let u = taskId.uuidString.lowercased()
        var ids: [String] = []
        for i in 0 ..< 8 {
            ids.append("\(idPrefix)\(u).timed-\(i)")
        }
        ids.append("\(idPrefix)\(u).allday-18")
        ids.append("\(idPrefix)\(u).allday-21")
        return ids
    }

    private nonisolated static func debugDate(_ date: Date?) -> String {
        guard let date else { return "nil" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f.string(from: date)
    }
}
