import Combine
import CoreLocation
import Foundation
import SwiftUI

enum GhostModeOption: String, CaseIterable, Identifiable {
    case pauseOneHour
    case untilTonight
    case keepHidden
    case stopHiding

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
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
    /// 名册 membership.id → family_profiles.id（Live 读库种子用）。
    @Published private(set) var profileIdByMembershipId: [UUID: UUID] = [:]

    private let locationStateService: LocationStateDataService
    private let membershipService: HouseholdMembershipDataService

    private var householdId: UUID?
    private var currentMembershipId: UUID?
    private var currentProfileId: UUID?
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

    func bind(householdId: UUID?, currentMembershipId: UUID?, currentProfileId: UUID?) {
        self.householdId = householdId
        self.currentMembershipId = currentMembershipId
        self.currentProfileId = currentProfileId
    }

    /// 先用会话内缓存坐标更新地图，避免离线/弱网时等待 GPS。
    func applyCachedDeviceLocationForMap() {
        guard currentMembershipId != nil else { return }
        guard let cached = LastKnownDeviceLocation.cachedCoordinate() else { return }
        currentUserLiveLocation = LocationPayload(
            latitude: cached.latitude,
            longitude: cached.longitude
        )
        syncCurrentUserBatteryFromDevice()
    }

    /// 进入位置 Tab 时调用：读取本机 GPS 并更新地图；非隐身时再按距离规则上报服务端。
    func captureCurrentUserLocationForMap(timeoutSeconds: TimeInterval? = nil) async {
        guard currentMembershipId != nil else { return }

        let isOffline = await NetworkMonitor.shared.isConnected == false
        let coordinate: CLLocationCoordinate2D?
        if isOffline {
            if let cached = LastKnownDeviceLocation.cachedCoordinate() {
                coordinate = cached
            } else {
                coordinate = await DeviceLocationFetcher.currentCoordinate(timeoutSeconds: 2)
            }
        } else if let timeoutSeconds {
            coordinate = await DeviceLocationFetcher.currentCoordinate(timeoutSeconds: timeoutSeconds)
        } else {
            coordinate = await DeviceLocationFetcher.currentCoordinate()
        }
        guard let coordinate else { return }
        let payload = LocationPayload(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        currentUserLiveLocation = payload
        LastKnownDeviceLocation.record(latitude: payload.latitude, longitude: payload.longitude)
        syncCurrentUserBatteryFromDevice()

        guard let householdId, let currentProfileId, isCurrentUserGhost == false else { return }
        guard await NetworkMonitor.shared.isConnected else { return }

        do {
            _ = try await locationStateService.reportCurrentLocationIfNeeded(
                householdId: householdId,
                profileId: currentProfileId,
                coordinate: payload,
                minDistanceMeters: SupabaseLocationStateDataService.defaultMinUpdateDistanceMeters,
                minIntervalSeconds: SupabaseLocationStateDataService.defaultMinUpdateIntervalSeconds
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

        if await NetworkMonitor.shared.isConnected == false {
            if let cachedMembers = await HouseholdLocalCache.loadMembers(for: householdId) {
                let filtered = cachedMembers.filteredToActiveMembers(in: householdId)
                let locationRecords = await HouseholdLocalCache.loadLocationStates(for: householdId) ?? []
                members = LocationMemberAssembler.buildMembers(
                    roster: HouseholdMemberRoster(
                        profiles: filtered.profiles,
                        memberships: filtered.members
                    ),
                    locationRecords: locationRecords,
                    householdId: householdId,
                    currentMembershipId: currentMembershipId
                )
                profileIdByMembershipId = Dictionary(
                    uniqueKeysWithValues: filtered.members.compactMap { membership in
                        guard let profileId = membership.profileId else { return nil }
                        return (membership.id, profileId)
                    }
                )
                reconcileSelectionAfterReload()
            }
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
                #if DEBUG
                let withCoordinates = locationRecords.filter { $0.latestLocation != nil }.count
                print(
                    "[LocationMainViewModel] location_states rows=\(locationRecords.count) "
                        + "withCoordinates=\(withCoordinates) household=\(householdId.uuidString.prefix(8))"
                )
                #endif
            } catch {
                #if DEBUG
                print("[LocationMainViewModel] location_states fetch failed (members still shown): \(error.localizedDescription)")
                #endif
            }
            await reconcileCurrentUserGhostStateIfNeeded(in: householdId)

            profileIdByMembershipId = Dictionary(
                uniqueKeysWithValues: roster.memberships.compactMap { membership in
                    guard let profileId = membership.profileId else { return nil }
                    return (membership.id, profileId)
                }
            )
            members = LocationMemberAssembler.buildMembers(
                roster: roster,
                locationRecords: locationRecords,
                householdId: householdId,
                currentMembershipId: currentMembershipId
            )
            if !locationRecords.isEmpty {
                HouseholdLocalCache.saveLocationStates(locationRecords, for: householdId)
            }
            #if DEBUG
            print(
                "[LocationMainViewModel] map members=\(members.count) "
                    + "visibleOnMap=\(members.filter(\.isVisibleOnMap).count) "
                    + "rosterMemberships=\(roster.memberships.count)"
            )
            #endif
            syncCurrentUserBatteryFromDevice()
            reconcileSelectionAfterReload()
        } catch {
            members = []
            errorMessage = error.localizedDescription
        }
    }

    func isSelected(memberID: UUID) -> Bool {
        if isCurrentUserSelectionLocked(memberID: memberID) {
            return true
        }
        return selectedMemberIDs.contains(memberID)
    }

    func setSelected(_ selected: Bool, for memberID: UUID) {
        if isCurrentUserSelectionLocked(memberID: memberID) {
            return
        }
        guard let member = members.first(where: { $0.id == memberID }), member.isSelectableOnMap else {
            return
        }
        if selected {
            selectedMemberIDs.insert(memberID)
        } else {
            selectedMemberIDs.remove(memberID)
        }
    }

    /// 当前登录成员始终在地图上展示，列表勾选不可取消。
    func isCurrentUserSelectionLocked(memberID: UUID) -> Bool {
        guard let currentMembershipId, memberID == currentMembershipId else { return false }
        return members.first(where: { $0.id == memberID })?.isCurrentUser == true
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
        guard let householdId, let currentProfileId else { return }

        switch option {
        case .pauseOneHour:
            LocationGhostPreferences.applyTimedGhost(
                until: Date().addingTimeInterval(3_600),
                for: currentProfileId
            )
        case .untilTonight:
            LocationGhostPreferences.applyTimedGhost(
                until: endOfToday(),
                for: currentProfileId
            )
        case .keepHidden:
            LocationGhostPreferences.applyPersistentGhost(for: currentProfileId)
        case .stopHiding:
            LocationGhostPreferences.clearGhostPreferences(for: currentProfileId)
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
                profileId: currentProfileId,
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
        guard let currentProfileId else { return }

        do {
            let record = try await locationStateService.fetchLocationState(
                householdId: householdId,
                profileId: currentProfileId
            )
            guard let record else { return }
            guard LocationGhostPreferences.shouldClearDatabaseGhostAfterReconcile(
                databaseFlag: record.isGhostMode,
                profileId: currentProfileId
            ) else { return }

            _ = try await locationStateService.updateGhostMode(
                householdId: householdId,
                profileId: currentProfileId,
                isGhostMode: false
            )
            LocationGhostPreferences.clearGhostPreferences(for: currentProfileId)
        } catch {
            #if DEBUG
            print("[LocationMainViewModel] ghost reconcile skipped: \(error.localizedDescription)")
            #endif
        }
    }

    private func reconcileSelectionAfterReload() {
        let selectableIDs = Set(members.filter(\.isSelectableOnMap).map(\.id))
        let visibleIDs = Set(members.filter(\.isVisibleOnMap).map(\.id))
        let virtualIDs = Set(members.filter(\.isVirtualMember).map(\.id))
        let defaultVisibleIDs = visibleIDs.subtracting(virtualIDs)
        let defaultSelectableIDs = selectableIDs.subtracting(virtualIDs)

        selectedMemberIDs = selectedMemberIDs.intersection(selectableIDs)
        if selectedMemberIDs.isEmpty {
            selectedMemberIDs = defaultVisibleIDs.isEmpty == false
                ? defaultVisibleIDs
                : defaultSelectableIDs
        }
        pinCurrentUserInSelection()
    }

    private func pinCurrentUserInSelection() {
        guard let currentMembershipId,
              members.contains(where: { $0.id == currentMembershipId && $0.isCurrentUser }) else {
            return
        }
        selectedMemberIDs.insert(currentMembershipId)
    }

    private func endOfToday() -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1)
            ?? Date().addingTimeInterval(86_400)
    }
}
