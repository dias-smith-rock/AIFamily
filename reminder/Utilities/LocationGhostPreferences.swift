import Foundation

/// 位置隐身（仅本机，按群组 + 档案隔离）：开启后不上报新坐标；不向服务器同步 `is_ghost_mode`。
enum LocationGhostPreferences {
    private static func storageKey(householdId: UUID, profileId: UUID) -> String {
        "location.ghostEnabled.\(householdId.uuidString.lowercased()).\(profileId.uuidString.lowercased())"
    }

    static func isEnabled(householdId: UUID, profileId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: storageKey(householdId: householdId, profileId: profileId))
    }

    static func setEnabled(_ enabled: Bool, householdId: UUID, profileId: UUID) {
        UserDefaults.standard.set(
            enabled,
            forKey: storageKey(householdId: householdId, profileId: profileId)
        )
    }

    static func shouldSkipLocationUpload(householdId: UUID, profileId: UUID) -> Bool {
        isEnabled(householdId: householdId, profileId: profileId)
    }
}
