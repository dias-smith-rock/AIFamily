import Foundation

/// 位置隐身：默认全员可见；仅用户手动选择后才隐身。
/// - **计时时效**（暂停 1 小时 / 直到今晚）：仅存本机截止时间，不写库。
/// - **保持隐藏**：写入 `location_states.is_ghost_mode = true`，全家可见为隐身。
enum LocationGhostPreferences {
    private enum GhostIntent: String {
        case timed
        case persistent
    }

    private static func hiddenUntilKey(for membershipId: UUID) -> String {
        "location.ghostUntil.\(membershipId.uuidString.lowercased())"
    }

    private static func intentKey(for membershipId: UUID) -> String {
        "location.ghostIntent.\(membershipId.uuidString.lowercased())"
    }

    static func hiddenUntil(for membershipId: UUID) -> Date? {
        let interval = UserDefaults.standard.double(
            forKey: hiddenUntilKey(for: membershipId)
        )
        guard interval > 0 else { return nil }
        let date = Date(timeIntervalSince1970: interval)
        return date > Date() ? date : nil
    }

    static func setHiddenUntil(_ date: Date?, for membershipId: UUID) {
        let key = hiddenUntilKey(for: membershipId)
        if let date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func applyTimedGhost(until: Date, for membershipId: UUID) {
        setHiddenUntil(until, for: membershipId)
        UserDefaults.standard.set(GhostIntent.timed.rawValue, forKey: intentKey(for: membershipId))
    }

    static func applyPersistentGhost(for membershipId: UUID) {
        setHiddenUntil(nil, for: membershipId)
        UserDefaults.standard.set(GhostIntent.persistent.rawValue, forKey: intentKey(for: membershipId))
    }

    static func clearGhostPreferences(for membershipId: UUID) {
        setHiddenUntil(nil, for: membershipId)
        UserDefaults.standard.removeObject(forKey: intentKey(for: membershipId))
    }

    /// 本机当前成员是否应视为隐身（计时中或库中已标记保持隐藏）。
    static func isEffectivelyGhost(databaseFlag: Bool, membershipId: UUID) -> Bool {
        if hiddenUntil(for: membershipId) != nil {
            return true
        }
        return databaseFlag
    }

    /// 地图上其他成员是否隐身：仅依据其服务端「保持隐藏」标记（无本机计时数据）。
    static func isGhostOnServer(record: LocationStateRecord?) -> Bool {
        record?.isGhostMode == true
    }

    /// 计时结束后若库中仍有陈旧 `is_ghost_mode`（旧版误写入），自动恢复为可见。
    static func reconcileStaleDatabaseGhostIfNeeded(
        databaseFlag: Bool,
        membershipId: UUID
    ) -> Bool {
        guard databaseFlag else { return false }
        guard hiddenUntil(for: membershipId) == nil else { return true }
        let intent = UserDefaults.standard.string(forKey: intentKey(for: membershipId))
        if intent == GhostIntent.persistent.rawValue {
            return true
        }
        return false
    }

    static func shouldClearDatabaseGhostAfterReconcile(
        databaseFlag: Bool,
        membershipId: UUID
    ) -> Bool {
        databaseFlag && reconcileStaleDatabaseGhostIfNeeded(
            databaseFlag: databaseFlag,
            membershipId: membershipId
        ) == false
    }
}
