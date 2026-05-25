import Foundation

/// 日程 / 任务主页的全局视图模式（与 Apple Calendar 类似的分栏）。
enum CalendarViewMode: String, CaseIterable {
    case list = "List"
    case day = "Day"
    case threeDay = "3 Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"

    /// 顶栏视图切换菜单中当前可用的模式（未实现的选项暂不展示）。
    static let menuCases: [CalendarViewMode] = [.list, .day]

    var menuTitle: String {
        switch self {
        case .list: return String(localized: "List")
        case .day: return String(localized: "Day")
        case .threeDay: return String(localized: "3 Day")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .year: return String(localized: "Year")
        }
    }
}
