import SwiftUI

/// 日程页当前选中的「日历日」（`startOfDay`），供 Tab 外层（如 AI 助理 Sheet）读取。
enum ScheduleSelectedDayPreferenceKey: PreferenceKey {
    static var defaultValue: Date? { nil }

    static func reduce(value: inout Date?, nextValue: () -> Date?) {
        if let next = nextValue() {
            value = next
        }
    }
}
