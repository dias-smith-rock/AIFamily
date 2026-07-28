import Combine
import Foundation
import SwiftUI
import UIKit
import EventKit

@MainActor
final class CalendarSyncViewModel: ObservableObject {
    @Published var calendars: [EventKitCalendarDescriptor] = []
    @Published var selectedCalendarIds: Set<String> = CalendarSyncPreferences.selectedCalendarIds
    @Published var continuousEnabled: Bool = CalendarSyncPreferences.continuousSyncEnabled
    @Published var isRequestingAccess = false
    @Published var isSyncing = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var lastSyncedAt: Date? = CalendarSyncPreferences.lastSyncedAt

    private let eventKit = EventKitCalendarService.shared

    var hasAccess: Bool {
        eventKit.hasAccess
    }

    var authorizationDenied: Bool {
        eventKit.refreshAuthorizationStatus()
        let status = eventKit.authorizationStatus
        if #available(iOS 17.0, *) {
            return status == .denied || status == .restricted || status == .writeOnly
        }
        return status == .denied || status == .restricted
    }

    func onAppear() {
        eventKit.refreshAuthorizationStatus()
        reloadCalendars()
        selectedCalendarIds = CalendarSyncPreferences.selectedCalendarIds
        continuousEnabled = CalendarSyncPreferences.continuousSyncEnabled
        lastSyncedAt = CalendarSyncPreferences.lastSyncedAt
        if hasAccess {
            CalendarInboundSyncCoordinator.shared.ensureChangeObservationStarted()
        }
    }

    func requestAccess() async {
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        errorMessage = nil
        let granted = await eventKit.requestAccess()
        reloadCalendars()
        if granted == false {
            errorMessage = AppLocalized.localized(L10n.Settings.calendarSyncPermissionNeeded)
        }
    }

    func toggleCalendar(_ id: String) {
        if selectedCalendarIds.contains(id) {
            selectedCalendarIds.remove(id)
        } else {
            selectedCalendarIds.insert(id)
        }
        CalendarSyncPreferences.selectedCalendarIds = selectedCalendarIds
    }

    func setContinuousEnabled(_ enabled: Bool) {
        continuousEnabled = enabled
        CalendarSyncPreferences.continuousSyncEnabled = enabled
        if enabled {
            CalendarInboundSyncCoordinator.shared.ensureChangeObservationStarted()
        }
    }

    func reloadCalendars() {
        calendars = eventKit.availableCalendars()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func sync(
        householdId: UUID?,
        membershipId: UUID?
    ) async {
        errorMessage = nil
        statusMessage = nil
        guard let householdId else {
            errorMessage = AppLocalized.localized(L10n.Settings.calendarSyncSelectGroup)
            return
        }
        guard let membershipId else {
            errorMessage = AppLocalized.localized(L10n.Auth.sessionAbnormalRetry)
            return
        }
        guard selectedCalendarIds.isEmpty == false else {
            errorMessage = AppLocalized.localized(L10n.Settings.calendarSyncNoCalendarsSelected)
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            if eventKit.hasAccess == false {
                let granted = await eventKit.requestAccess()
                guard granted else {
                    throw CalendarInboundSyncError.accessDenied
                }
                reloadCalendars()
            }

            CalendarSyncPreferences.continuousSyncEnabled = continuousEnabled
            let result = try await CalendarInboundSyncCoordinator.shared.sync(
                householdId: householdId,
                membershipId: membershipId,
                calendarIds: selectedCalendarIds,
                reason: "manualSettings"
            )
            lastSyncedAt = CalendarSyncPreferences.lastSyncedAt
            statusMessage = L10n.Settings.calendarSyncResult.formatted(
                locale: AppSettingsManager.shared.appLocale,
                Int64(result.fetchedCount),
                Int64(result.createdCount),
                Int64(result.updatedCount)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sourceLabel(for kind: EventKitCalendarSourceKind) -> L10n.Entry {
        switch kind {
        case .apple: return L10n.Settings.calendarSyncSourceApple
        case .google: return L10n.Settings.calendarSyncSourceGoogle
        case .other: return L10n.Settings.calendarSyncSourceOther
        }
    }
}
