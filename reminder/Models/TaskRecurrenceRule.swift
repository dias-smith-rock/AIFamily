import Foundation
import SwiftUI

/// 任务重复规则（与 `tasks.recurrence_rule` / `recurrence_interval` 映射）。
enum TaskRecurrenceRule: String, CaseIterable, Identifiable, Sendable, Equatable {
    case none
    case daily
    case weekdays
    case weekends
    case weekly
    case monthly
    case yearly
    case custom

    var id: String { rawValue }

    var titleKey: LocalizedStringResource {
        switch self {
        case .none: L10n.Common.doesNotRepeat.localized
        case .daily: L10n.Common.daily.localized
        case .weekdays: L10n.Common.weekdays.localized
        case .weekends: L10n.Common.weekends.localized
        case .weekly: L10n.Common.weekly.localized
        case .monthly: L10n.Common.monthly2.localized
        case .yearly: L10n.Common.yearly2.localized
        case .custom: L10n.Common.everyFewDays.localized
        }
    }

    /// 写入 `tasks.recurrence_rule` 的 iCalendar 片段；`none` 为 `nil`。
    func recurrenceRuleString(customDayInterval: Int) -> String? {
        switch self {
        case .none:
            return nil
        case .daily:
            return "FREQ=DAILY;INTERVAL=1"
        case .weekdays:
            return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .weekends:
            return "FREQ=WEEKLY;BYDAY=SA,SU"
        case .weekly:
            return "FREQ=WEEKLY"
        case .monthly:
            return "FREQ=MONTHLY"
        case .yearly:
            return "FREQ=YEARLY"
        case .custom:
            let n = max(2, min(365, customDayInterval))
            return "FREQ=DAILY;INTERVAL=\(n)"
        }
    }

    /// 从已有 `recurrence_rule` + `recurrence_interval` 反推表单选项。
    static func inferred(from recurrenceRule: String?, recurrenceInterval: Int?) -> TaskRecurrenceRule {
        guard let raw = recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return .none
        }
        let u = raw.uppercased()

        if u.contains("FREQ=YEARLY") {
            return .yearly
        }
        if u.contains("FREQ=MONTHLY") {
            return .monthly
        }

        if u.contains("FREQ=DAILY") {
            let interval = Self.parseInterval(from: u) ?? recurrenceInterval ?? 1
            if interval > 1 {
                return .custom
            }
            return .daily
        }

        if u.contains("FREQ=WEEKLY") {
            if u.contains("BYDAY=MO,TU,WE,TH,FR") || u.contains("BYDAY=MO,TU,WE,TH,FR,") {
                return .weekdays
            }
            let bydayUpper = u.components(separatedBy: "BYDAY=").dropFirst().first?.prefix(while: { $0 != ";" && $0 != " " }) ?? Substring()
            let b = String(bydayUpper).uppercased()
            if b.contains("SA"), b.contains("SU"), b.contains("MO") == false {
                return .weekends
            }
            return .weekly
        }

        return .none
    }

    /// 从规则串解析 `INTERVAL=`（无则 `nil`）。
    static func parseInterval(from ruleUppercased: String) -> Int? {
        guard let range = ruleUppercased.range(of: "INTERVAL=") else { return nil }
        let tail = ruleUppercased[range.upperBound...]
        let digits = tail.prefix(while: { $0.isNumber })
        guard digits.isEmpty == false else { return nil }
        return Int(digits)
    }
}
