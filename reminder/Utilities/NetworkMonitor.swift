import Combine
import Foundation
import Network

/// 系统网络路径监测；离线时跳过 Supabase 请求，优先展示磁盘缓存。
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    private(set) var isConnected = false
    private(set) var hasReceivedInitialPathUpdate = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.aifamily.networkmonitor", qos: .utility)
    private var initialPathWaiters: [CheckedContinuation<Bool, Never>] = []

    private init() {
        isConnected = monitor.currentPath.status == .satisfied
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = connected
                if self.hasReceivedInitialPathUpdate == false {
                    self.hasReceivedInitialPathUpdate = true
                    LoginFlowPerformanceTracing.logAlways(
                        "networkMonitor.initialPath",
                        note: "connected=\(connected)"
                    )
                    let waiters = self.initialPathWaiters
                    self.initialPathWaiters.removeAll()
                    for waiter in waiters {
                        waiter.resume(returning: connected)
                    }
                }
            }
        }
        monitor.start(queue: queue)
    }

    /// 冷启动时等待 NWPathMonitor 首次回调，避免误判 offline。
    func waitForInitialPathUpdate(timeoutNanoseconds: UInt64 = 300_000_000) async -> Bool {
        if hasReceivedInitialPathUpdate {
            return isConnected
        }

        let waitStart = CFAbsoluteTimeGetCurrent()
        let connected = await withCheckedContinuation { continuation in
            initialPathWaiters.append(continuation)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard hasReceivedInitialPathUpdate == false else { return }
                hasReceivedInitialPathUpdate = true
                let waiters = initialPathWaiters
                initialPathWaiters.removeAll()
                let fallbackConnected = isConnected
                LoginFlowPerformanceTracing.logAlways(
                    "networkMonitor.initialPath",
                    note: "connected=\(fallbackConnected) source=timeout"
                )
                for waiter in waiters {
                    waiter.resume(returning: fallbackConnected)
                }
            }
        }
        let waitMs = Int((CFAbsoluteTimeGetCurrent() - waitStart) * 1000)
        LoginFlowPerformanceTracing.logAlways(
            "networkMonitor.waitForInitialPathUpdate",
            note: "connected=\(connected) waitMs=\(waitMs)"
        )
        return connected
    }

    /// Bootstrap 前确保已收到首帧网络状态（必要时短暂等待）。
    func ensureInitialPathReady() async -> Bool {
        await waitForInitialPathUpdate()
    }
}
