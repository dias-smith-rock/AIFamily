import Combine
import UIKit

/// 读取本机电量（`UIDevice`），供地图标注与 Live 广播使用。
@MainActor
final class DeviceBatteryMonitor: ObservableObject {
    static let shared = DeviceBatteryMonitor()

    @Published private(set) var batteryLevel: Int = 100
    @Published private(set) var isCharging: Bool = false

    private var observers: [NSObjectProtocol] = []

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        observers = [
            NotificationCenter.default.addObserver(
                forName: UIDevice.batteryLevelDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            },
            NotificationCenter.default.addObserver(
                forName: UIDevice.batteryStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            },
        ]
    }

    func refresh() {
        let snapshot = Self.readSnapshot()
        batteryLevel = snapshot.level
        isCharging = snapshot.isCharging
    }

    static func readSnapshot() -> (level: Int, isCharging: Bool) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let device = UIDevice.current
        let charging = device.batteryState == .charging || device.batteryState == .full
        let fraction = device.batteryLevel
        let level: Int
        if fraction < 0 {
            level = 100
        } else {
            level = min(100, max(0, Int((fraction * 100).rounded())))
        }
        return (level, charging)
    }
}
