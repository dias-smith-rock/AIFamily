import Foundation
import SwiftUI

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

    var menuTitleKey: LocalizedStringKey {
        switch self {
        case .list: return "List"
        case .day: return "Day"
        case .threeDay: return "3 Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}
