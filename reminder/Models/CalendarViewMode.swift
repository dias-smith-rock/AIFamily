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
    static let menuCases: [CalendarViewMode] = [.list, .day, .week]

    var menuTitleKey: LocalizedStringResource {
        switch self {
        case .list: return L10n.Common.list.localized
        case .day: return L10n.Common.day.localized
        case .threeDay: return L10n.Common.n3Day.localized
        case .week: return L10n.Common.week.localized
        case .month: return L10n.Common.month.localized
        case .year: return L10n.Common.year.localized
        }
    }
}
