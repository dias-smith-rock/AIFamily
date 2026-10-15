import Foundation

/// 把当前家庭的未完成日程写进小组件快照。
enum ScheduleWidgetPublisher {
    static func publish(tasks: [FamilyTask], householdId: UUID?) {
        guard let householdId else {
            ScheduleWidgetSnapshotStore.clear()
            return
        }
        let calendar = AppDisplayTimeZone.calendar()
        let now = Date()
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start,
              let windowStart = calendar.date(byAdding: .month, value: -1, to: monthStart),
              let windowEnd = calendar.date(byAdding: .month, value: 2, to: monthStart) else {
            return
        }

        let items = tasks.compactMap { task -> ScheduleWidgetTask? in
            guard task.householdId == householdId else { return nil }
            guard task.isScheduledCalendarTask else { return nil }
            switch task.status {
            case .completed, .cancelled:
                return nil
            default:
                break
            }
            let day = task.scheduleDisplayDay(displayCalendar: calendar)
            guard day >= windowStart, day < windowEnd else { return nil }
            let minutes: Int?
            if task.isAllDay {
                minutes = nil
            } else {
                let start = task.scheduleStartDate
                minutes = calendar.component(.hour, from: start) * 60
                    + calendar.component(.minute, from: start)
            }
            return ScheduleWidgetTask(
                id: task.id,
                title: task.title,
                year: calendar.component(.year, from: day),
                month: calendar.component(.month, from: day),
                day: calendar.component(.day, from: day),
                isAllDay: task.isAllDay,
                minutesFromMidnight: minutes
            )
        }

        let snapshot = ScheduleWidgetSnapshot(
            householdId: householdId,
            generatedAt: now,
            localeIdentifier: AppSettingsManager.shared.appLocale.identifier,
            timeZoneIdentifier: calendar.timeZone.identifier,
            tasks: items
        )
        ScheduleWidgetSnapshotStore.save(snapshot)
    }
}
