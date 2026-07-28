import Foundation

extension FamilyTask {
    /// 任务语义时区：库中 `timezone`，否则回退显示时区/系统时区。
    var resolvedTimeZone: TimeZone {
        TaskCalendar.timeZone(forTaskTimezone: timezone)
    }

    var taskCalendar: Calendar {
        TaskCalendar.calendar(forTaskTimezone: timezone)
    }

    /// 日程日过滤用的展示日：定时按显示时区落日；全天按任务时区 Y/M/D 映射到显示时区同名日。
    func scheduleDisplayDay(displayCalendar: Calendar = AppDisplayTimeZone.calendar()) -> Date {
        if isAllDay, let due = dueDate ?? originalDueDate {
            return TaskCalendar.allDayDisplayDay(
                dueDate: due,
                taskTimezone: timezone,
                displayCalendar: displayCalendar
            )
        }
        return displayCalendar.startOfDay(for: scheduleStartDate)
    }
}
