import Foundation

/// 本地优先同步入口：flush Outbox 后通知各 VM 从服务端拉取。
@MainActor
enum LocalFirstSyncCoordinator {
    private static var isSyncing = false
    private static var debounceTask: Task<Void, Never>?
    private static var pendingReason: String?

    /// 立即同步（启动 / 联网 / 回前台）。
    static func syncNow(reason: String) async {
        guard await NetworkMonitor.shared.isConnected else {
            #if DEBUG
            print("[LocalFirstSync] skip offline reason=\(reason)")
            #endif
            return
        }
        guard isSyncing == false else {
            pendingReason = reason
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            if let pending = pendingReason {
                pendingReason = nil
                Task { await syncNow(reason: pending) }
            }
        }

        #if DEBUG
        print("[LocalFirstSync] begin reason=\(reason)")
        #endif
        await TaskOfflineOutbox.shared.flushIfNeeded()
        await ListOfflineOutbox.shared.flushIfNeeded()
        // 即使队列为空也要拉服务端，保证其他设备的变更能进来。
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        #if DEBUG
        print("[LocalFirstSync] end reason=\(reason)")
        #endif
    }

    /// 本地写后的合并同步（短防抖，避免连续勾选刷爆）。
    static func requestSync(reason: String) {
        pendingReason = reason
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard Task.isCancelled == false else { return }
            let resolved = pendingReason ?? reason
            pendingReason = nil
            await syncNow(reason: resolved)
        }
    }
}
