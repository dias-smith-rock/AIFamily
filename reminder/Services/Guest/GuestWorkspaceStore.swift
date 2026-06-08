import Foundation

/// 游客工作区内存 + 磁盘一致性写入（供 Guest*DataService 使用）。
actor GuestWorkspaceStore {
    static let shared = GuestWorkspaceStore()

    private var snapshot: GuestWorkspaceSnapshot

    init(snapshot: GuestWorkspaceSnapshot? = nil) {
        self.snapshot = snapshot ?? GuestSessionStore.loadOrCreate()
    }

    func reloadFromDisk() {
        snapshot = GuestSessionStore.loadOrCreate()
    }

    func currentSnapshot() -> GuestWorkspaceSnapshot {
        snapshot
    }

    func replace(_ newSnapshot: GuestWorkspaceSnapshot) {
        snapshot = newSnapshot
        GuestSessionStore.save(newSnapshot)
    }

    func mutate(_ transform: (inout GuestWorkspaceSnapshot) -> Void) {
        transform(&snapshot)
        GuestSessionStore.save(snapshot)
    }
}
