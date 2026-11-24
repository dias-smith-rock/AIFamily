import Foundation

/// 把「今天和我有关」的日程、未完成待办、未勾清单写进小组件快照。
enum ScheduleWidgetPublisher {
    private static var viewerProfileId: UUID?

    static func publish(tasks: [FamilyTask], householdId: UUID?, profileId: UUID? = nil) {
        if let profileId {
            viewerProfileId = profileId
        }
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
        let profileId = profileId ?? viewerProfileId
        let today = calendar.startOfDay(for: now)
        var items: [ScheduleWidgetTask] = []

        for task in tasks where task.householdId == householdId && isOpen(task) && isMine(task, profileId: profileId) {
            if task.isScheduledCalendarTask {
                let day = calendar.startOfDay(for: task.scheduleDisplayDay(displayCalendar: calendar))
                guard day >= windowStart, day < windowEnd else { continue }
                items.append(widgetTask(task, day: day, calendar: calendar, source: "schedule"))
            } else if task.isFlexibleTodoCandidate {
                let deadline = task.flexibleDeadlineDay.map { calendar.startOfDay(for: $0) }
                let day: Date
                if let deadline, deadline >= today, deadline < windowEnd {
                    day = deadline
                } else {
                    day = today
                }
                guard day >= windowStart, day < windowEnd else { continue }
                items.append(widgetTask(task, day: day, calendar: calendar, source: "todo", allDay: true))
            }
        }

        items.append(contentsOf: uncheckedListItems(householdId: householdId, today: today, calendar: calendar))

        let snapshot = ScheduleWidgetSnapshot(
            householdId: householdId,
            generatedAt: now,
            localeIdentifier: AppSettingsManager.shared.appLocale.identifier,
            timeZoneIdentifier: calendar.timeZone.identifier,
            tasks: items
        )
        ScheduleWidgetSnapshotStore.save(snapshot)
    }

    static func refreshFromCache(householdId: UUID?, profileId: UUID? = nil) {
        guard let householdId else {
            publish(tasks: [], householdId: nil, profileId: profileId)
            return
        }
        let tasks = HouseholdLocalCache.loadTasksNow(for: householdId) ?? []
        publish(tasks: tasks, householdId: householdId, profileId: profileId)
    }

    private static func isOpen(_ task: FamilyTask) -> Bool {
        switch task.status {
        case .completed, .cancelled:
            return false
        default:
            return true
        }
    }

    /// 指定了负责人时只留给这个人；没指定的家庭事项，当前成员也能在桌面看到。
    private static func isMine(_ task: FamilyTask, profileId: UUID?) -> Bool {
        var ids = task.targetProfileIds ?? []
        if let targetProfileId = task.targetProfileId {
            ids.append(targetProfileId)
        }
        if ids.isEmpty { return true }
        guard let profileId else { return false }
        return ids.contains(profileId)
    }

    private static func widgetTask(
        _ task: FamilyTask,
        day: Date,
        calendar: Calendar,
        source: String,
        allDay: Bool? = nil
    ) -> ScheduleWidgetTask {
        let isAllDay = allDay ?? task.isAllDay
        let minutes: Int?
        if isAllDay {
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
            isAllDay: isAllDay,
            minutesFromMidnight: minutes,
            source: source
        )
    }

    private static func uncheckedListItems(
        householdId: UUID,
        today: Date,
        calendar: Calendar
    ) -> [ScheduleWidgetTask] {
        let lists = HouseholdLocalCache.loadListsNow(for: householdId) ?? []
        var items: [ScheduleWidgetTask] = []
        for list in lists {
            let rows = HouseholdLocalCache.loadListItemsNow(for: list.id) ?? []
            for item in rows where item.isChecked == false {
                guard items.count < 8 else { return items }
                items.append(
                    ScheduleWidgetTask(
                        id: item.id,
                        title: item.title,
                        year: calendar.component(.year, from: today),
                        month: calendar.component(.month, from: today),
                        day: calendar.component(.day, from: today),
                        isAllDay: true,
                        minutesFromMidnight: nil,
                        source: "list"
                    )
                )
            }
        }
        return items
    }
}
