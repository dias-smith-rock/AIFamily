import Foundation

/// 本机日历同步偏好（EventKit calendarIdentifier 为设备侧 ID）。
enum CalendarSyncPreferences {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let selectedCalendarIds = "calendar_sync_selected_calendar_ids"
        static let householdId = "calendar_sync_household_id"
        static let membershipId = "calendar_sync_membership_id"
        static let continuousEnabled = "calendar_sync_continuous_enabled"
        static let lastSyncedAt = "calendar_sync_last_synced_at"
    }

    static var selectedCalendarIds: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.selectedCalendarIds) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.selectedCalendarIds) }
    }

    static var householdId: UUID? {
        get {
            guard let raw = defaults.string(forKey: Key.householdId) else { return nil }
            return UUID(uuidString: raw)
        }
        set { defaults.set(newValue?.uuidString, forKey: Key.householdId) }
    }

    static var membershipId: UUID? {
        get {
            guard let raw = defaults.string(forKey: Key.membershipId) else { return nil }
            return UUID(uuidString: raw)
        }
        set { defaults.set(newValue?.uuidString, forKey: Key.membershipId) }
    }

    static var continuousSyncEnabled: Bool {
        get {
            if defaults.object(forKey: Key.continuousEnabled) == nil { return true }
            return defaults.bool(forKey: Key.continuousEnabled)
        }
        set { defaults.set(newValue, forKey: Key.continuousEnabled) }
    }

    static var lastSyncedAt: Date? {
        get {
            let interval = defaults.double(forKey: Key.lastSyncedAt)
            guard interval > 0 else { return nil }
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: Key.lastSyncedAt)
            } else {
                defaults.removeObject(forKey: Key.lastSyncedAt)
            }
        }
    }

    static var isConfiguredForSync: Bool {
        householdId != nil
            && membershipId != nil
            && selectedCalendarIds.isEmpty == false
            && continuousSyncEnabled
    }
}
