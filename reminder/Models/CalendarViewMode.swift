import Foundation

/// 日程 / 任务主页的全局视图模式（与 Apple Calendar 类似的分栏）。
enum CalendarViewMode: String, CaseIterable {
    case list = "List"
    case day = "Day"
    case threeDay = "3 Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
}
