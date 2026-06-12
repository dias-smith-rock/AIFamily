import Foundation
import SwiftUI

// MARK: - Household

enum HouseholdStatus: String, Codable, Equatable {
    case active
    case suspended
    case deleted
}

enum SubscriptionPlan: String, Codable, Equatable {
    case free
    case proWeekly = "pro_weekly"
    case proMonthly = "pro_monthly"
    case proYearly = "pro_yearly"
    case proLifetime = "pro_lifetime"
    case proOneYearFree = "pro_1_year_free"
}

// MARK: - Membership

enum MembershipRole: String, Codable, Equatable {
    case creator
    case admin
    case member

    /// 列表副标题、详情等用的简短中文标签（非 SwiftUI 上下文可用）。
    var displayTitle: String {
        switch self {
        case .creator: return L10n.Common.creator.string()
        case .admin: return L10n.Common.admin.string()
        case .member: return L10n.Common.member.string()
        }
    }

    /// UI 展示用（键与 `Localizable.xcstrings` 一致）。
    var localizedName: LocalizedStringKey {
        switch self {
        case .creator: L10n.Common.creator.localized
        case .admin: L10n.Common.admin.localized
        case .member: L10n.Common.member.localized
        }
    }
}

enum MembershipStatus: String, Codable, Equatable {
    case pending
    case active
    case disabled
}

enum ContactMethod: String, Codable, Equatable, CaseIterable {
    case appPush = "app_push"
    case wechat
    case email
}

// MARK: - Task

enum TaskStatus: String, Codable, Equatable, Sendable {
    case new
    case accepted
    case inProgress = "in_progress"
    case completed
    case issue
    case failed
    case expired
    case cancelled

    /// UI 展示用（键与 `Localizable.xcstrings` 一致，勿使用 `rawValue`）。
    var localizedName: LocalizedStringKey {
        switch self {
        case .new: L10n.Common.pending.localized
        case .accepted: L10n.Common.accepted.localized
        case .inProgress: L10n.Common.inProgress.localized
        case .completed: L10n.Common.completed.localized
        case .issue: L10n.Common.encounteredAProblem.localized
        case .failed: L10n.Common.failed.localized
        case .expired: L10n.Common.expired.localized
        case .cancelled: L10n.Common.cancelled.localized
        }
    }
}

enum TaskPriority: String, Codable, Equatable, CaseIterable {
    case low
    case normal
    case high
    case urgent

    var localizedName: LocalizedStringKey {
        switch self {
        case .urgent, .high: L10n.Common.urgent.localized
        case .normal, .low: L10n.Common.normal.localized
        }
    }
}

/// 任务创建来源（`tasks.source`）。
enum TaskSource: String, Codable, Equatable {
    case manual
    case googleCalendar = "google_calendar"
    case appleCalendar = "apple_calendar"
    case publicHoliday = "public_holiday"
    case hermesWechat = "hermes_wechat"

    /// 外部同步日程：应用内不可编辑。
    var isReadOnly: Bool {
        switch self {
        case .googleCalendar, .appleCalendar, .publicHoliday:
            return true
        case .manual, .hermesWechat:
            return false
        }
    }
}

// MARK: - Subscription Order

enum PaymentMethod: String, Codable, Equatable {
    case appleIAP = "apple_iap"
    case wechatPay = "wechat_pay"
    case alipay
}

enum OrderStatus: String, Codable, Equatable {
    case pending
    case success
    case completed
    case failed
    case refunded
}
