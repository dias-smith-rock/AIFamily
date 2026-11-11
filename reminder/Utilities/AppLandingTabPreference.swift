import Foundation

/// 冷启动进入主界面时的默认 Tab：固定为 Schedule。
enum AppLandingTabPreference: Equatable {
    case todos
    case schedule

    static func resolve(
        tasks: [FamilyTask],
        calendar: Calendar = AppDisplayTimeZone.calendar(),
        now: Date = Date()
    ) -> AppLandingTabPreference {
        _ = tasks
        _ = calendar
        _ = now
        return .schedule
    }
}
