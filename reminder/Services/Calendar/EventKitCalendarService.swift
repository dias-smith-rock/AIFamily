import Foundation
import EventKit

/// 系统日历（EventKit）只读访问：授权、列表、拉取、变更通知。
@MainActor
final class EventKitCalendarService {
    static let shared = EventKitCalendarService()

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    private(set) var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    var hasAccess: Bool {
        if #available(iOS 17.0, *) {
            return authorizationStatus == .fullAccess
        }
        return authorizationStatus == .authorized
    }

    private init() {}

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    @discardableResult
    func requestAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
            refreshAuthorizationStatus()
            return granted && hasAccess
        } catch {
            refreshAuthorizationStatus()
            return false
        }
    }

    func availableCalendars() -> [EventKitCalendarDescriptor] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { EventKitCalendarDescriptor(calendar: $0) }
    }

    func fetchEvents(
        calendarIdentifiers: Set<String>,
        start: Date,
        end: Date
    ) -> [EKEvent] {
        guard hasAccess, calendarIdentifiers.isEmpty == false else { return [] }
        let calendars = store.calendars(for: .event).filter { calendarIdentifiers.contains($0.calendarIdentifier) }
        guard calendars.isEmpty == false else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
    }

    /// 订阅系统日历变更；回调在主线程。
    func startObservingChanges(_ handler: @escaping () -> Void) {
        stopObservingChanges()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            handler()
        }
    }

    func stopObservingChanges() {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
    }
}

struct EventKitCalendarDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceLabel: EventKitCalendarSourceKind
    let taskSource: TaskSource

    init(calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
        let kind = EventKitCalendarSourceKind.from(calendar.source)
        sourceLabel = kind
        taskSource = kind.taskSource
    }
}

enum EventKitCalendarSourceKind: String, Hashable {
    case apple
    case google
    case other

    var taskSource: TaskSource {
        switch self {
        case .google: return .googleCalendar
        case .apple, .other: return .appleCalendar
        }
    }

    static func from(_ source: EKSource?) -> EventKitCalendarSourceKind {
        guard let source else { return .other }
        let title = source.title.lowercased()
        if title.contains("google") {
            return .google
        }
        switch source.sourceType {
        case .calDAV:
            // Google 常以 CalDAV 出现；已用 title 判断 Google。
            return title.contains("icloud") || title.contains("apple") ? .apple : .other
        case .local, .mobileMe, .exchange, .birthdays:
            return .apple
        case .subscribed:
            return .other
        @unknown default:
            return .other
        }
    }
}

enum EventKitSyncRefs {
    static let namespace = "eventkit"
    static let eventIdentifierKey = "event_identifier"
    static let calendarIdentifierKey = "calendar_identifier"
    static let storeSourceKey = "store_source"

    static func make(
        eventIdentifier: String,
        calendarIdentifier: String,
        storeSource: EventKitCalendarSourceKind
    ) -> [String: [String: String]] {
        [
            namespace: [
                eventIdentifierKey: eventIdentifier,
                calendarIdentifierKey: calendarIdentifier,
                storeSourceKey: storeSource.rawValue
            ]
        ]
    }

    static func eventIdentifier(from refs: [String: [String: String]]?) -> String? {
        refs?[namespace]?[eventIdentifierKey]
    }
}
