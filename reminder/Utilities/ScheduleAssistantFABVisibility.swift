import SwiftUI

/// 日程 Tab 内子页面（如任务详情）通过该 Preference 请求隐藏全局 AI 悬浮球。
enum ScheduleAssistantFABVisibility {
    struct PreferenceKey: SwiftUI.PreferenceKey {
        static var defaultValue: Bool { false }

        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = value || nextValue()
        }
    }
}
