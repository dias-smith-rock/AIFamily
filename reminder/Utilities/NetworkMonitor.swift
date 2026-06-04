import Combine
import Foundation
import Network

/// 系统网络路径监测；离线时跳过 Supabase 请求，优先展示磁盘缓存。
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    private(set) var isConnected = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.aifamily.networkmonitor", qos: .utility)

    private init() {
        isConnected = monitor.currentPath.status == .satisfied
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
}
