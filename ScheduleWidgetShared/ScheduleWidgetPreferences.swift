import Foundation
import WidgetKit

/// 主 App 与小组件共用的 App Group 偏好（默认关闭农历）。
enum ScheduleWidgetPreferences {
    static let appGroupID = ScheduleWidgetSnapshotStore.appGroupID
    private static let showLunarDateKey = "schedule.widget.showLunarDate"

    /// 小组件是否显示农历日期；未写入时为 `false`。
    static var showsLunarDate: Bool {
        get {
            UserDefaults(suiteName: appGroupID)?.bool(forKey: showLunarDateKey) ?? false
        }
        set {
            guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
            defaults.set(newValue, forKey: showLunarDateKey)
            WidgetCenter.shared.reloadTimelines(ofKind: ScheduleWidgetKind.calendar)
        }
    }
}

/// 农历短文案（如「十月初二」），供小组件展示；月日均用中文。
enum LunarDateFormatting {
    private static let monthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    private static let dayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    static func shortLabel(for date: Date) -> String {
        var calendar = Calendar(identifier: .chinese)
        calendar.locale = Locale(identifier: "zh_CN")
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        guard (1...12).contains(month), (1...30).contains(day) else { return "" }

        let monthName = monthNames[month - 1]
        let dayName = dayNames[day - 1]
        let isLeapMonth = calendar.dateComponents([.month], from: date).isLeapMonth == true
        return (isLeapMonth ? "闰" : "") + monthName + dayName
    }
}

/// 中国常见节假日 / 传统节日名称（公历 + 农历）。
enum ChineseHolidayLookup {
    static func name(on date: Date, gregorian: Calendar = .current) -> String? {
        if let solar = solarHolidayName(on: date, calendar: gregorian) {
            return solar
        }
        return lunarHolidayName(on: date)
    }

    private static func solarHolidayName(on date: Date, calendar: Calendar) -> String? {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        switch (month, day) {
        case (1, 1): return "元旦"
        case (2, 14): return "情人节"
        case (3, 8): return "妇女节"
        case (3, 12): return "植树节"
        case (4, _):
            return isQingming(date, calendar: calendar) ? "清明节" : nil
        case (5, 1): return "劳动节"
        case (5, 4): return "青年节"
        case (6, 1): return "儿童节"
        case (7, 1): return "建党节"
        case (8, 1): return "建军节"
        case (9, 10): return "教师节"
        case (10, 1): return "国庆节"
        case (12, 25): return "圣诞节"
        default: return nil
        }
    }

    private static func lunarHolidayName(on date: Date) -> String? {
        var calendar = Calendar(identifier: .chinese)
        calendar.locale = Locale(identifier: "zh_CN")
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return nil }
        if components.isLeapMonth == true { return nil }

        switch (month, day) {
        case (1, 1): return "春节"
        case (1, 15): return "元宵节"
        case (5, 5): return "端午节"
        case (7, 7): return "七夕"
        case (7, 15): return "中元节"
        case (8, 15): return "中秋节"
        case (9, 9): return "重阳节"
        case (12, 8): return "腊八节"
        case (12, 23), (12, 24): return "小年"
        default:
            break
        }

        // 除夕：农历腊月最后一天。
        if month == 12, isLastDayOfChineseMonth(date, calendar: calendar) {
            return "除夕"
        }
        return nil
    }

    private static func isLastDayOfChineseMonth(_ date: Date, calendar: Calendar) -> Bool {
        guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return false }
        return calendar.component(.month, from: next) != calendar.component(.month, from: date)
            || calendar.dateComponents([.month], from: next).isLeapMonth
                != calendar.dateComponents([.month], from: date).isLeapMonth
    }

    /// 清明约在公历 4 月 4–6 日，按年份估算。
    private static func isQingming(_ date: Date, calendar: Calendar) -> Bool {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        guard month == 4 else { return false }
        let estimated = Int(Double(year - 1900) * 0.2422 + 5.07) - ((year - 1900) / 4)
        return day == estimated
    }
}
