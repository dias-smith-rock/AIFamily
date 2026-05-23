import Foundation

// MARK: - 重复任务实体化展开

/// 根据母任务的 `recurrence_rule` / `recurrence_interval` / `recurrence_end_date` 生成子任务实例（内存态，写入前需再经 PostgREST）。
enum RecurrenceEngine {

    /// 母任务：`recurrence_rule` 非空且 `parentTaskId == nil`。
    /// 产出：若干子任务，`parentTaskId` 指向母任务 `id`，`dueDate` 为推算出的各次发生时间，`id` 均为新 UUID，`recurrence_*` 在子任务上为 `nil`。
    static func generateInstances(from motherTask: FamilyTask) -> [FamilyTask] {
        let dates = occurrenceDates(for: motherTask)
        guard dates.count > 1 else { return [] }
        let calendar = Calendar.current
        let now = Date()
        return dates.dropFirst().map { dayAnchor in
            childCopy(mother: motherTask, occurrenceDay: dayAnchor, calendar: calendar, materializedAt: now)
        }
    }

    /// 包含母任务首次 `dueDate` 在内的所有发生日（时间分量与母任务首次执行时间对齐）。
    static func occurrenceDates(for motherTask: FamilyTask) -> [Date] {
        guard motherTask.isRecurringSeriesMother else { return [] }
        guard let rule = motherTask.recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines), rule.isEmpty == false else {
            return []
        }
        guard let anchor = motherTask.dueDate else { return [] }

        let calendar = Calendar.current
        let parsed = ParsedRecurrence(raw: rule, recurrenceInterval: motherTask.recurrenceInterval)
        let endCap = motherTask.recurrenceEndDate
            ?? calendar.date(byAdding: .year, value: 2, to: anchor)
            ?? anchor

        var dates: [Date] = [anchor]
        var cursor = anchor
        let maxCount = 800

        while dates.count < maxCount {
            guard let next = nextOccurrence(after: cursor, anchor: anchor, parsed: parsed, calendar: calendar) else { break }
            let nextDay = calendar.startOfDay(for: next)
            let capDay = calendar.startOfDay(for: endCap)
            if nextDay > capDay { break }
            dates.append(next)
            cursor = next
        }
        return dates
    }

    // MARK: - 时间合并（批量「修改此后所有」）

    /// 将编辑器上的时分秒套到「某次发生」的日历日上，**不改动**该次发生的年月日（全日任务则对齐到该日日初）。
    static func mergeEditorTime(editorDue: Date, ontoOccurrence occurrence: Date?, allDay: Bool, calendar: Calendar = .current) -> Date {
        guard let occurrence else { return editorDue }
        if allDay {
            return calendar.startOfDay(for: occurrence)
        }
        let timeParts = calendar.dateComponents([.hour, .minute, .second], from: editorDue)
        let dayStart = calendar.startOfDay(for: occurrence)
        return calendar.date(
            bySettingHour: timeParts.hour ?? 0,
            minute: timeParts.minute ?? 0,
            second: timeParts.second ?? 0,
            of: dayStart
        ) ?? occurrence
    }

    // MARK: - Private

    private struct ParsedRecurrence {
        enum Kind {
            case daily
            case weeklySimple
            case weeklyByWeekdays(Set<Int>)
            case monthly
            case yearly
        }

        let kind: Kind
        let interval: Int

        init(raw: String, recurrenceInterval: Int?) {
            let u = raw.uppercased()
            let interval = TaskRecurrenceRule.parseInterval(from: u) ?? recurrenceInterval ?? 1
            self.interval = max(1, interval)

            if u.contains("FREQ=YEARLY") {
                kind = .yearly
            } else if u.contains("FREQ=MONTHLY") {
                kind = .monthly
            } else if u.contains("FREQ=DAILY") {
                kind = .daily
            } else if u.contains("FREQ=WEEKLY") {
                if u.contains("BYDAY=") {
                    let set = Self.weekdaySet(from: u)
                    if set.isEmpty == false {
                        kind = .weeklyByWeekdays(set)
                    } else {
                        kind = .weeklySimple
                    }
                } else {
                    kind = .weeklySimple
                }
            } else {
                kind = .daily
            }
        }

        private static func weekdaySet(from uppercased: String) -> Set<Int> {
            guard let range = uppercased.range(of: "BYDAY=") else { return [] }
            let tail = uppercased[range.upperBound...]
            let tokenString = tail.prefix(while: { $0 != ";" && $0 != " " })
            let tokens = tokenString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var set = Set<Int>()
            for t in tokens {
                if let w = RecurrenceEngine.icalWeekdayToCalendarWeekday(String(t)) {
                    set.insert(w)
                }
            }
            return set
        }
    }

    /// iCalendar `MO`…`SU` → `Calendar` `.weekday`（1=周日 … 7=周六，与常见 `Calendar` 行为一致）。
    private static func icalWeekdayToCalendarWeekday(_ token: String) -> Int? {
        switch token.uppercased() {
        case "SU": return 1
        case "MO": return 2
        case "TU": return 3
        case "WE": return 4
        case "TH": return 5
        case "FR": return 6
        case "SA": return 7
        default: return nil
        }
    }

    private static func nextOccurrence(
        after cursor: Date,
        anchor: Date,
        parsed: ParsedRecurrence,
        calendar: Calendar
    ) -> Date? {
        switch parsed.kind {
        case .daily:
            return calendar.date(byAdding: .day, value: parsed.interval, to: cursor)

        case .weeklySimple:
            return calendar.date(byAdding: .weekOfYear, value: parsed.interval, to: cursor)

        case .weeklyByWeekdays(let weekdays):
            guard let day = nextEligibleWeekday(after: cursor, weekdays: weekdays, calendar: calendar) else { return nil }
            return applyingTime(from: anchor, onto: day, calendar: calendar)

        case .monthly:
            return calendar.date(byAdding: .month, value: parsed.interval, to: cursor)

        case .yearly:
            return calendar.date(byAdding: .year, value: parsed.interval, to: cursor)
        }
    }

    private static func nextEligibleWeekday(after reference: Date, weekdays: Set<Int>, calendar: Calendar) -> Date? {
        guard let probeStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference)) else { return nil }
        var probe = probeStart
        for _ in 0 ..< 480 {
            let wd = calendar.component(.weekday, from: probe)
            if weekdays.contains(wd) {
                return probe
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: probe) else { return nil }
            probe = nextDay
        }
        return nil
    }

    private static func applyingTime(from reference: Date, onto day: Date, calendar: Calendar) -> Date {
        let t = calendar.dateComponents([.hour, .minute, .second], from: reference)
        let dayStart = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: t.second ?? 0, of: dayStart) ?? day
    }

    private static func childCopy(mother: FamilyTask, occurrenceDay: Date, calendar: Calendar, materializedAt: Date) -> FamilyTask {
        let newDue = applyingTime(from: mother.dueDate ?? occurrenceDay, onto: occurrenceDay, calendar: calendar)
        let newEnd = childEndDatetime(mother: mother, childDue: newDue)
        return FamilyTask(
            id: UUID(),
            householdId: mother.householdId,
            creatorId: mother.creatorId,
            parentTaskId: mother.id,
            groupId: nil,
            originalDueDate: nil,
            involvedMemberIds: mother.involvedMemberIds,
            targetProfileId: mother.targetProfileId,
            targetProfileIds: mother.targetProfileIds,
            targetSubject: mother.targetSubject,
            title: mother.title,
            description: mother.description,
            originalPrompt: mother.originalPrompt,
            attachmentUrls: mother.attachmentUrls,
            externalContacts: mother.externalContacts,
            locationData: mother.locationData,
            externalSyncRefs: mother.externalSyncRefs,
            alarmSetBy: mother.alarmSetBy,
            status: mother.status,
            priority: mother.priority,
            dueDate: newDue,
            endDatetime: newEnd,
            durationMinutes: mother.durationMinutes,
            isAllDay: mother.isAllDay,
            recurrenceRule: nil,
            recurrenceEndDate: nil,
            recurrenceInterval: nil,
            reminderOffsets: mother.reminderOffsets,
            estimatedCost: mother.estimatedCost,
            backgroundColor: mother.backgroundColor,
            emergencyPhone: mother.emergencyPhone,
            createdAt: materializedAt,
            updatedAt: materializedAt
        )
    }

    private static func childEndDatetime(mother: FamilyTask, childDue: Date) -> Date? {
        guard let motherDue = mother.dueDate, let motherEnd = mother.endDatetime else { return nil }
        let delta = motherEnd.timeIntervalSince(motherDue)
        return childDue.addingTimeInterval(delta)
    }
}
