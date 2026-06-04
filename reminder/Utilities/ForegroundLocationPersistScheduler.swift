import Foundation

/// 后台定位关闭时：应用保持在前台期间定时尝试位置入库（Release 5 分钟，Debug 10 秒）。
@MainActor
final class ForegroundLocationPersistScheduler {
    static let shared = ForegroundLocationPersistScheduler()
    static var refreshIntervalSeconds: UInt64 {
        #if DEBUG
        return 10
        #else
        return 5 * 60
        #endif
    }

    private var refreshTask: Task<Void, Never>?
    private var householdId: UUID?
    private var profileId: UUID?
    private var locationStateService: LocationStateDataService?
    private init() {}

    func updateContext(
        householdId: UUID?,
        profileId: UUID?,
        locationStateService: LocationStateDataService
    ) {
        self.householdId = householdId
        self.profileId = profileId
        self.locationStateService = locationStateService
    }

    func startIfNeeded() {
        guard BackgroundLocationPreferences.isEnabled == false else {
            stop()
            return
        }
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: Self.refreshIntervalSeconds * 1_000_000_000)
                guard Task.isCancelled == false else { break }
                await self.firePeriodicRefresh()
            }
        }
        #if DEBUG
        print("[LocationPersist] scheduler started interval=\(Self.refreshIntervalSeconds)s")
        #endif
    }

    func stop(reason: String = "manual") {
        refreshTask?.cancel()
        refreshTask = nil
        print("[LocationPersist] scheduler stopped reason=\(reason)")
    }

    private func firePeriodicRefresh() async {
        guard BackgroundLocationPreferences.isEnabled == false else { return }
        guard ForegroundLocationPersistEligibility.shared.canPersist else { return }
        guard let householdId, let profileId, let locationStateService else { return }

        await LocationStartupReporter.report(
            trigger: .foregroundPeriodicRefresh,
            householdId: householdId,
            profileId: profileId,
            locationStateService: locationStateService
        )
    }
}
