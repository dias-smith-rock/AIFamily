import Foundation

/// 本地优先同步入口：flush Outbox 后通知各 VM 从服务端拉取。
@MainActor
enum LocalFirstSyncCoordinator {
    private static var isSyncing = false
    private static var debounceTask: Task<Void, Never>?
    private static var pendingReason: String?
    private static var retryTask: Task<Void, Never>?

    /// 仅冲 Outbox（供 loadTasks 拉网前调用，避免再发通知造成递归）。
    static func flushOutboxesOnly(reason: String) async {
        guard await NetworkMonitor.shared.isConnected else { return }
        #if DEBUG
        print("[LocalFirstSync] flushOnly reason=\(reason)")
        #endif
        _ = await TaskOfflineOutbox.shared.flushIfNeeded()
        await ListOfflineOutbox.shared.flushIfNeeded()
        if TaskOfflineOutbox.shared.pendingCount > 0 {
            scheduleRetryIfNeeded()
        }
    }

    /// 立即同步（启动 / 联网 / 回前台 / 下拉刷新）：flush + 通知拉取。
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
        await flushOutboxesOnly(reason: reason)
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        NotificationCenter.default.post(name: .plannerListsDidChange, object: nil)
        #if DEBUG
        print(
            "[LocalFirstSync] end reason=\(reason) taskPending=\(TaskOfflineOutbox.shared.pendingCount)"
        )
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

    private static func scheduleRetryIfNeeded() {
        guard retryTask == nil else { return }
        retryTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            retryTask = nil
            guard Task.isCancelled == false else { return }
            guard TaskOfflineOutbox.shared.pendingCount > 0 else { return }
            await syncNow(reason: "pendingRetry")
        }
    }
}
