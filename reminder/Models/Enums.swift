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
}

// MARK: - Membership

enum MembershipRole: String, Codable, Equatable {
    case creator
    case admin
    case member

    /// 列表副标题、详情等用的简短中文标签。
    var displayTitle: String {
        switch self {
        case .creator: return String(localized: "Creator")
        case .admin: return String(localized: "Admin")
        case .member: return String(localized: "Member")
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
        case .new: "Pending acceptance"
        case .accepted: "Accepted"
        case .inProgress: "In progress"
        case .completed: "Completed"
        case .issue: "Issue reported"
        case .failed: "Failed"
        case .expired: "Expired"
        case .cancelled: "Cancelled"
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
        case .urgent, .high: "🔴 Urgent"
        case .normal, .low: "🟢 Normal"
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
    case failed
    case refunded
}
