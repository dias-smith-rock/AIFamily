import Foundation

/// 客户端定时隐身（「暂停 1 小时」「直到今晚」），与库中 `is_ghost_mode` 叠加判断。
enum LocationGhostPreferences {
    private static func storageKey(for membershipId: UUID) -> String {
        "location.ghostUntil.\(membershipId.uuidString.lowercased())"
    }

    static func hiddenUntil(for membershipId: UUID) -> Date? {
        let interval = UserDefaults.standard.double(
            forKey: storageKey(for: membershipId)
        )
        guard interval > 0 else { return nil }
        let date = Date(timeIntervalSince1970: interval)
        return date > Date() ? date : nil
    }

    static func setHiddenUntil(_ date: Date?, for membershipId: UUID) {
        let key = storageKey(for: membershipId)
        if let date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func isEffectivelyGhost(databaseFlag: Bool, membershipId: UUID) -> Bool {
        if databaseFlag { return true }
        return hiddenUntil(for: membershipId) != nil
    }
}
