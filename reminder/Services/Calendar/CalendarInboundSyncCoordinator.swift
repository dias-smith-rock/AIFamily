import Foundation
import EventKit

struct CalendarInboundSyncResult: Equatable {
    var createdCount: Int = 0
    var updatedCount: Int = 0
    var skippedCount: Int = 0
    var fetchedCount: Int = 0

    var touchedCount: Int { createdCount + updatedCount }
}

enum CalendarInboundSyncError: LocalizedError {
    case missingHousehold
    case missingMembership
    case noCalendarsSelected
    case accessDenied
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingHousehold:
            return AppLocalized.localizedSync(L10n.Settings.calendarSyncSelectGroup)
        case .missingMembership:
            return AppLocalized.localizedSync(L10n.Auth.sessionAbnormalRetry)
        case .noCalendarsSelected:
            return AppLocalized.localizedSync(L10n.Settings.calendarSyncNoCalendarsSelected)
        case .accessDenied:
            return AppLocalized.localizedSync(L10n.Settings.calendarSyncPermissionNeeded)
        case .syncFailed(let message):
            return message
        }
    }
}

/// Calendar → App 单向导入 / 增量同步。
@MainActor
final class CalendarInboundSyncCoordinator {
    static let shared = CalendarInboundSyncCoordinator()

    private let eventKit = EventKitCalendarService.shared
    private var debounceTask: Task<Void, Never>?
    private var isSyncing = false
    private var isObserving = false

    private init() {}

    private var taskService: TaskDataService {
        AppBootstrapLocator.shared?.services.taskService ?? ReminderServiceContainer.mock().taskService
    }

    func ensureChangeObservationStarted() {
        guard isObserving == false else { return }
        isObserving = true
        eventKit.startObservingChanges { [weak self] in
            self?.scheduleDebouncedSync(reason: "ekEventStoreChanged")
        }
    }

    func scheduleDebouncedSync(reason: String, delayNanoseconds: UInt64 = 800_000_000) {
        guard CalendarSyncPreferences.isConfiguredForSync else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard Task.isCancelled == false else { return }
            _ = try? await self?.syncIfConfigured(reason: reason)
        }
    }

    @discardableResult
    func syncIfConfigured(reason: String) async throws -> CalendarInboundSyncResult? {
        guard CalendarSyncPreferences.isConfiguredForSync else { return nil }
        guard let householdId = CalendarSyncPreferences.householdId,
              let membershipId = CalendarSyncPreferences.membershipId else {
            return nil
        }
        return try await sync(
            householdId: householdId,
            membershipId: membershipId,
            calendarIds: CalendarSyncPreferences.selectedCalendarIds,
            reason: reason
        )
    }

    @discardableResult
    func sync(
        householdId: UUID,
        membershipId: UUID,
        calendarIds: Set<String>,
        reason: String
    ) async throws -> CalendarInboundSyncResult {
        _ = reason
        guard isSyncing == false else {
            return CalendarInboundSyncResult()
        }
        isSyncing = true
        defer { isSyncing = false }

        eventKit.refreshAuthorizationStatus()
        guard eventKit.hasAccess else {
            throw CalendarInboundSyncError.accessDenied
        }
        guard calendarIds.isEmpty == false else {
            throw CalendarInboundSyncError.noCalendarsSelected
        }

        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .year, value: -1, to: now) ?? now
        let end = cal.date(byAdding: .year, value: 2, to: now) ?? now
        let events = eventKit.fetchEvents(calendarIdentifiers: calendarIds, start: start, end: end)

        let existing = try await taskService.fetchTasks(in: householdId)
        var byEventId: [String: FamilyTask] = [:]
        for task in existing {
            if let eventId = EventKitSyncRefs.eventIdentifier(from: task.externalSyncRefs) {
                byEventId[eventId] = task
            }
        }

        let calendarLookup = Dictionary(
            uniqueKeysWithValues: eventKit.availableCalendars().map { ($0.id, $0) }
        )

        var result = CalendarInboundSyncResult(fetchedCount: events.count)
        var seenEventIds = Set<String>()

        for event in events {
            guard let eventId = event.eventIdentifier, eventId.isEmpty == false else {
                result.skippedCount += 1
                continue
            }
            if seenEventIds.contains(eventId) {
                result.skippedCount += 1
                continue
            }
            seenEventIds.insert(eventId)

            let calendarId = event.calendar?.calendarIdentifier ?? ""
            let descriptor = calendarLookup[calendarId]
            let sourceKind = descriptor?.sourceLabel ?? EventKitCalendarSourceKind.from(event.calendar?.source)
            let taskSource = descriptor?.taskSource ?? sourceKind.taskSource
            let draft = Self.makeDraft(
                from: event,
                householdId: householdId,
                membershipId: membershipId,
                calendarIdentifier: calendarId,
                sourceKind: sourceKind,
                taskSource: taskSource
            )

            if var existingTask = byEventId[eventId] {
                let changed = Self.applyInboundFields(from: draft, onto: &existingTask)
                if changed {
                    _ = try await taskService.updateTask(existingTask)
                    result.updatedCount += 1
                } else {
                    result.skippedCount += 1
                }
            } else {
                _ = try await taskService.createTask(draft, geofence: nil)
                result.createdCount += 1
            }
        }

        CalendarSyncPreferences.householdId = householdId
        CalendarSyncPreferences.membershipId = membershipId
        CalendarSyncPreferences.selectedCalendarIds = calendarIds
        CalendarSyncPreferences.lastSyncedAt = Date()
        ensureChangeObservationStarted()

        if result.touchedCount > 0 {
            NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        }
        return result
    }

    private static func makeDraft(
        from event: EKEvent,
        householdId: UUID,
        membershipId: UUID,
        calendarIdentifier: String,
        sourceKind: EventKitCalendarSourceKind,
        taskSource: TaskSource
    ) -> FamilyTask {
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start.addingTimeInterval(TimeInterval(FamilyTask.defaultDurationMinutes * 60))
        let durationMinutes = max(
            1,
            Int(round(end.timeIntervalSince(start) / 60))
        )
        let rawTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = rawTitle.isEmpty
            ? AppLocalized.localized(L10n.Settings.calendarSyncUntitled)
            : rawTitle
        let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationName = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        var locationData: FamilyTask.LocationData?
        if let locationName, locationName.isEmpty == false {
            locationData = FamilyTask.LocationData(
                name: locationName,
                address: locationName,
                latitude: event.structuredLocation?.geoLocation?.coordinate.latitude,
                longitude: event.structuredLocation?.geoLocation?.coordinate.longitude
            )
        }

        let eventId = event.eventIdentifier ?? UUID().uuidString
        let refs = EventKitSyncRefs.make(
            eventIdentifier: eventId,
            calendarIdentifier: calendarIdentifier,
            storeSource: sourceKind
        )

        return FamilyTask(
            id: UUID(),
            householdId: householdId,
            creatorId: membershipId,
            involvedMemberIds: nil,
            title: resolvedTitle,
            description: (notes?.isEmpty == false) ? notes : nil,
            locationData: locationData,
            externalSyncRefs: refs,
            status: .new,
            priority: .normal,
            source: taskSource,
            taskType: TaskTypeKind.scheduled.rawValue,
            dueDate: start,
            endDatetime: end,
            durationMinutes: event.isAllDay ? FamilyTask.defaultDurationMinutes : durationMinutes,
            isAllDay: event.isAllDay,
            recurrenceRule: rruleString(from: event),
            recurrenceInterval: event.recurrenceRules?.first != nil ? 1 : nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private static func applyInboundFields(from draft: FamilyTask, onto task: inout FamilyTask) -> Bool {
        var changed = false
        if task.title != draft.title {
            task.title = draft.title
            changed = true
        }
        if task.description != draft.description {
            task.description = draft.description
            changed = true
        }
        if task.dueDate != draft.dueDate {
            task.dueDate = draft.dueDate
            changed = true
        }
        if task.endDatetime != draft.endDatetime {
            task.endDatetime = draft.endDatetime
            changed = true
        }
        if task.isAllDay != draft.isAllDay {
            task.isAllDay = draft.isAllDay
            changed = true
        }
        if task.durationMinutes != draft.durationMinutes {
            task.durationMinutes = draft.durationMinutes
            changed = true
        }
        if task.locationData != draft.locationData {
            task.locationData = draft.locationData
            changed = true
        }
        if task.recurrenceRule != draft.recurrenceRule {
            task.recurrenceRule = draft.recurrenceRule
            changed = true
        }
        if task.externalSyncRefs != draft.externalSyncRefs {
            task.externalSyncRefs = draft.externalSyncRefs
            changed = true
        }
        if task.source != draft.source {
            task.source = draft.source
            changed = true
        }
        return changed
    }

    private static func rruleString(from event: EKEvent) -> String? {
        guard let rule = event.recurrenceRules?.first else { return nil }
        switch rule.frequency {
        case .daily:
            let interval = max(1, rule.interval)
            return interval == 1 ? "FREQ=DAILY;INTERVAL=1" : "FREQ=DAILY;INTERVAL=\(interval)"
        case .weekly:
            return "FREQ=WEEKLY"
        case .monthly:
            return "FREQ=MONTHLY"
        case .yearly:
            return "FREQ=YEARLY"
        @unknown default:
            return nil
        }
    }
}

@MainActor
enum AppBootstrapLocator {
    static weak var shared: AppBootstrap?
}
