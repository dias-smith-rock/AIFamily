import Combine
import CoreLocation
import Foundation

enum GhostModeOption: String, CaseIterable, Identifiable {
    case pauseOneHour
    case untilTonight
    case keepHidden
    case stopHiding

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .pauseOneHour: "暂停 1 小时"
        case .untilTonight: "直到今晚"
        case .keepHidden: "保持隐藏"
        case .stopHiding: "停止隐藏"
        }
    }
}

@MainActor
final class LocationMainViewModel: ObservableObject {
    @Published private(set) var members: [UserLocationState] = []
    @Published var selectedMemberIDs: Set<UUID> = []
    @Published var isMemberListExpanded = false
    @Published var isGhostOptionsPresented = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// 本机刚读取的坐标，用于地图展示当前用户（隐身时亦显示，不一定写入服务端）。
    @Published private(set) var currentUserLiveLocation: LocationPayload?

    private let locationStateService: LocationStateDataService
    private let membershipService: HouseholdMembershipDataService

    private var householdId: UUID?
    private var currentMembershipId: UUID?
    /// 实时模式期间暂停隐身展示与上报拦截（不改变用户已保存的隐身偏好）。
    private(set) var isLiveModeActive = false
    private var batteryCancellable: AnyCancellable?

    init(
        locationStateService: LocationStateDataService,
        membershipService: HouseholdMembershipDataService,
        previewMembers: [UserLocationState]? = nil
    ) {
        self.locationStateService = locationStateService
        self.membershipService = membershipService
        if let previewMembers {
            members = previewMembers
            selectedMemberIDs = Set(previewMembers.filter(\.isSelectableOnMap).map(\.id))
        }

        let monitor = DeviceBatteryMonitor.shared
        monitor.refresh()
        batteryCancellable = monitor.$batteryLevel
            .combineLatest(monitor.$isCharging)
            .sink { [weak self] _, _ in
                self?.syncCurrentUserBatteryFromDevice()
            }
    }

    var currentUser: UserLocationState? {
        members.first(where: \.isCurrentUser)
    }

    var mapDisplayedMembers: [UserLocationState] {
        members.compactMap { member in
            let display = displayStateForMap(member)
            if member.isCurrentUser {
                return display.currentLocation != nil ? display : nil
            }
            guard selectedMemberIDs.contains(member.id), display.isVisibleOnMap else {
                return nil
            }
            return display
        }
    }

    var isCurrentUserGhost: Bool {
        guard isLiveModeActive == false else { return false }
        return currentUser?.isGhostMode == true
    }

    func setLiveModeActive(_ active: Bool) {
        isLiveModeActive = active
        if active {
            isGhostOptionsPresented = false
        }
    }

    func bind(householdId: UUID?, currentMembershipId: UUID?) {
        self.householdId = householdId
        self.currentMembershipId = currentMembershipId
    }

    /// 进入位置 Tab 时调用：读取本机 GPS 并更新地图；非隐身时再按距离规则上报服务端。
    func captureCurrentUserLocationForMap() async {
        guard currentMembershipId != nil else { return }

        guard let coordinate = await DeviceLocationFetcher.currentCoordinate() else { return }
        let payload = LocationPayload(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        currentUserLiveLocation = payload
        syncCurrentUserBatteryFromDevice()

        guard let householdId, let currentMembershipId, isCurrentUserGhost == false else { return }

        do {
            _ = try await locationStateService.reportCurrentLocationIfNeeded(
                householdId: householdId,
                membershipId: currentMembershipId,
                coordinate: payload,
                minDistanceMeters: SupabaseLocationStateDataService.defaultMinUpdateDistanceMeters
            )
        } catch {
            #if DEBUG
            print("[LocationMainViewModel] location report skipped: \(error.localizedDescription)")
            #endif
        }
    }

    func refresh() async {
        guard let householdId else {
            members = []
            selectedMemberIDs = []
            currentUserLiveLocation = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let roster = try await membershipService.fetchMemberRoster(in: householdId, activeOnly: false)
            var locationRecords: [LocationStateRecord] = []
            do {
                locationRecords = try await locationStateService.fetchLocationStates(in: householdId)
            } catch {
                #if DEBUG
                print("[LocationMainViewModel] location_states fetch failed (members still shown): \(error.localizedDescription)")
                #endif
            }
            await reconcileCurrentUserGhostStateIfNeeded(in: householdId)

            members = LocationMemberAssembler.buildMembers(
                roster: roster,
                locationRecords: locationRecords,
                currentMembershipId: currentMembershipId
            )
            syncCurrentUserBatteryFromDevice()
            reconcileSelectionAfterReload()
        } catch {
            members = []
            errorMessage = error.localizedDescription
        }
    }

    func isSelected(memberID: UUID) -> Bool {
        selectedMemberIDs.contains(memberID)
    }

    func setSelected(_ selected: Bool, for memberID: UUID) {
        guard let member = members.first(where: { $0.id == memberID }), member.isSelectableOnMap else {
            return
        }
        if selected {
            selectedMemberIDs.insert(memberID)
        } else {
            selectedMemberIDs.remove(memberID)
        }
    }

    func toggleMemberList() {
        isMemberListExpanded.toggle()
    }

    func collapseMemberList() {
        isMemberListExpanded = false
    }

    func presentGhostOptions() {
        guard isLiveModeActive == false else { return }
        isGhostOptionsPresented = true
    }

    func applyGhostOption(_ option: GhostModeOption) async {
        guard let householdId, let currentMembershipId else { return }

        switch option {
        case .pauseOneHour:
            LocationGhostPreferences.applyTimedGhost(
                until: Date().addingTimeInterval(3_600),
                for: currentMembershipId
            )
        case .untilTonight:
            LocationGhostPreferences.applyTimedGhost(
                until: endOfToday(),
                for: currentMembershipId
            )
        case .keepHidden:
            LocationGhostPreferences.applyPersistentGhost(for: currentMembershipId)
        case .stopHiding:
            LocationGhostPreferences.clearGhostPreferences(for: currentMembershipId)
        }

        let shouldPersistGhostInDatabase: Bool
        switch option {
        case .keepHidden:
            shouldPersistGhostInDatabase = true
        case .stopHiding, .pauseOneHour, .untilTonight:
            shouldPersistGhostInDatabase = false
        }

        do {
            _ = try await locationStateService.updateGhostMode(
                householdId: householdId,
                membershipId: currentMembershipId,
                isGhostMode: shouldPersistGhostInDatabase
            )
            await refresh()
            if option == .stopHiding {
                await captureCurrentUserLocationForMap()
                await refresh()
            } else {
                await captureCurrentUserLocationForMap()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncCurrentUserBatteryFromDevice() {
        guard let currentMembershipId,
              let index = members.firstIndex(where: { $0.id == currentMembershipId && $0.isCurrentUser }) else {
            return
        }
        let monitor = DeviceBatteryMonitor.shared
        guard members[index].batteryLevel != monitor.batteryLevel
            || members[index].isCharging != monitor.isCharging else {
            return
        }
        members[index].batteryLevel = monitor.batteryLevel
        members[index].isCharging = monitor.isCharging
    }

    private func displayStateForMap(_ member: UserLocationState) -> UserLocationState {
        var updated = member
        if member.isCurrentUser, let live = currentUserLiveLocation {
            updated.currentLocation = live
        }
        if member.isCurrentUser {
            let monitor = DeviceBatteryMonitor.shared
            updated.batteryLevel = monitor.batteryLevel
            updated.isCharging = monitor.isCharging
        }
        if isLiveModeActive, member.isCurrentUser {
            updated.isGhostMode = false
        }
        return updated
    }

    /// 旧版曾把计时时效写入 `is_ghost_mode`；计时结束后自动清库，避免长期误显示隐身。
    private func reconcileCurrentUserGhostStateIfNeeded(in householdId: UUID) async {
        guard let currentMembershipId else { return }

        do {
            let record = try await locationStateService.fetchLocationState(
                householdId: householdId,
                membershipId: currentMembershipId
            )
            guard let record else { return }
            guard LocationGhostPreferences.shouldClearDatabaseGhostAfterReconcile(
                databaseFlag: record.isGhostMode,
                membershipId: currentMembershipId
            ) else { return }

            _ = try await locationStateService.updateGhostMode(
                householdId: householdId,
                membershipId: currentMembershipId,
                isGhostMode: false
            )
            LocationGhostPreferences.clearGhostPreferences(for: currentMembershipId)
        } catch {
            #if DEBUG
            print("[LocationMainViewModel] ghost reconcile skipped: \(error.localizedDescription)")
            #endif
        }
    }

    private func reconcileSelectionAfterReload() {
        let selectableIDs = Set(members.filter(\.isSelectableOnMap).map(\.id))
        selectedMemberIDs = selectedMemberIDs.intersection(selectableIDs)
        if selectedMemberIDs.isEmpty {
            selectedMemberIDs = selectableIDs
        }
    }

    private func endOfToday() -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1)
            ?? Date().addingTimeInterval(86_400)
    }
}
