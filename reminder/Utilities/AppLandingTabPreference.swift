import Foundation

/// 冷启动进入主界面时的默认 Tab：有待办优先 Todos；否则有今日日程进 Schedule；皆无则 Todos。
enum AppLandingTabPreference: Equatable {
    case todos
    case schedule

    static func resolve(
        tasks: [FamilyTask],
        calendar: Calendar = AppDisplayTimeZone.calendar(),
        now: Date = Date()
    ) -> AppLandingTabPreference {
        if tasks.contains(where: isOpenFlexibleTodo) {
            return .todos
        }
        if tasks.contains(where: { isOpenScheduledTaskOnToday($0, calendar: calendar, now: now) }) {
            return .schedule
        }
        return .todos
    }

    private static func isOpenFlexibleTodo(_ task: FamilyTask) -> Bool {
        guard task.isFlexibleTodoCandidate else { return false }
        switch task.status {
        case .completed, .cancelled, .failed, .expired:
            return false
        default:
            return true
        }
    }

    private static func isOpenScheduledTaskOnToday(
        _ task: FamilyTask,
        calendar: Calendar,
        now: Date
    ) -> Bool {
        guard task.isScheduledCalendarTask else { return false }
        switch task.status {
        case .completed, .cancelled:
            return false
        default:
            break
        }
        let today = calendar.startOfDay(for: now)
        let day = task.scheduleDisplayDay(displayCalendar: calendar)
        return calendar.isDate(day, inSameDayAs: today)
    }
}
