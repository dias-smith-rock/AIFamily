import Foundation

/// `location_states` 坐标写入结果（供日志与调用方判断）。
enum LocationPersistOutcome: Sendable, Equatable {
    case persisted
    case skippedGhost
    case skippedWithinThreshold(distanceMeters: Double)
    case skippedWithinInterval(elapsedSeconds: Double)
}

enum LocationPersistTrigger: String, Sendable {
    case appLaunched
    case appEnteredForeground
    case appEnteringBackground
    case foregroundPeriodicRefresh
    case backgroundContinuous
}
