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
