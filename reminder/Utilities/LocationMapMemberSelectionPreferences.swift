import Foundation

/// Location 地图成员勾选（按群组隔离，本机 UserDefaults）。
enum LocationMapMemberSelectionPreferences {
    private static func storageKey(householdId: UUID) -> String {
        "location.mapSelectedMemberIDs.\(householdId.uuidString.lowercased())"
    }

    static func load(householdId: UUID) -> Set<UUID>? {
        guard let raw = UserDefaults.standard.array(forKey: storageKey(householdId: householdId)) as? [String] else {
            return nil
        }
        let ids = raw.compactMap { UUID(uuidString: $0) }
        guard ids.isEmpty == false else { return nil }
        return Set(ids)
    }

    static func save(_ memberIDs: Set<UUID>, householdId: UUID) {
        let strings = memberIDs.map { $0.uuidString.lowercased() }.sorted()
        UserDefaults.standard.set(strings, forKey: storageKey(householdId: householdId))
    }
}

/// Location 地图日期范围（按群组隔离，与成员勾选一样存在本机）。
enum LocationHistoryDateRangePreferences {
    private static func storageKey(householdId: UUID) -> String {
        "location.historyDateRange.\(householdId.uuidString.lowercased())"
    }

    private struct Payload: Codable {
        var kind: String
        var customStartDay: Date?
        var customEndDay: Date?
    }

    static func load(householdId: UUID) -> LocationHistoryDateRange? {
        let key = storageKey(householdId: householdId)
        guard let data = UserDefaults.standard.data(forKey: key) else {
            #if DEBUG
            let stored = UserDefaults.standard.object(forKey: key)
            print(
                "[HistoryRangeTrace] load miss key=\(key) "
                    + "storedType=\(stored.map { String(describing: type(of: $0)) } ?? "absent")"
            )
            #endif
            return nil
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            #if DEBUG
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
            print("[HistoryRangeTrace] load decode failed key=\(key) error=\(error) raw=\(raw)")
            #endif
            return nil
        }
        guard let kind = LocationHistoryDateRange.Kind(rawValue: payload.kind) else {
            #if DEBUG
            print("[HistoryRangeTrace] load unknown kind=\(payload.kind) key=\(key)")
            #endif
            return nil
        }
        #if DEBUG
        print("[HistoryRangeTrace] load hit kind=\(kind.rawValue) key=\(key)")
        #endif
        let calendar = AppDisplayTimeZone.calendar()
        let today = calendar.startOfDay(for: Date())
        let start = payload.customStartDay.map { calendar.startOfDay(for: $0) } ?? today
        let end = payload.customEndDay.map { calendar.startOfDay(for: $0) } ?? start
        return LocationHistoryDateRange(kind: kind, customStartDay: start, customEndDay: end)
    }

    static func save(_ range: LocationHistoryDateRange, householdId: UUID) {
        let payload = Payload(
            kind: range.kind.rawValue,
            customStartDay: range.kind == .custom ? range.customStartDay : nil,
            customEndDay: range.kind == .custom ? range.customEndDay : nil
        )
        let key = storageKey(householdId: householdId)
        guard let data = try? JSONEncoder().encode(payload) else {
            #if DEBUG
            print("[HistoryRangeTrace] save encode failed kind=\(payload.kind) key=\(key)")
            #endif
            return
        }
        UserDefaults.standard.set(data, forKey: key)
        #if DEBUG
        print("[HistoryRangeTrace] save wrote kind=\(payload.kind) bytes=\(data.count) key=\(key)")
        #endif
    }
}
