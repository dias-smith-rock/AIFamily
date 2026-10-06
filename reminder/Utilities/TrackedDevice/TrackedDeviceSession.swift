import Foundation

/// 追踪端本地会话：是否处于家长 PIN 解锁态（防误触，非安全边界）。
@MainActor
enum TrackedDeviceSession {
    private static let unlockedUntilKey = "trackedDevice.unlockedUntil"

    /// PIN 解锁后保持的分钟数；回到后台超时则锁回追踪壳。
    static let unlockDurationMinutes: TimeInterval = 15

    static var isUnlocked: Bool {
        let until = UserDefaults.standard.double(forKey: unlockedUntilKey)
        guard until > 0 else { return false }
        return Date().timeIntervalSince1970 < until
    }

    static func unlock() {
        let until = Date().addingTimeInterval(unlockDurationMinutes * 60).timeIntervalSince1970
        UserDefaults.standard.set(until, forKey: unlockedUntilKey)
    }

    static func lock() {
        UserDefaults.standard.removeObject(forKey: unlockedUntilKey)
    }

    static func refreshUnlockIfNeeded() {
        guard isUnlocked else { return }
        unlock()
    }
}
