import Foundation

/// Live Huddle 对等方最近一次广播的电量快照。
struct LivePeerBatteryState: Equatable, Sendable {
    let level: Int
    let isCharging: Bool

    var clampedLevel: Int {
        min(100, max(0, level))
    }
}
