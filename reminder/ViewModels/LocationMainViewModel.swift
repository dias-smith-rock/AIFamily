import Combine
import CoreLocation
import Foundation
import SwiftUI

@MainActor
final class LocationMainViewModel: ObservableObject {
    @Published private(set) var members: [UserLocationState] = []
    @Published var selectedMemberIDs: Set<UUID> = []
    @Published var isMemberListExpanded = false
    @Published var historyDateRange = LocationHistoryDateRange.today()
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// 本机刚读取的坐标，用于地图展示当前用户（隐身时亦显示，不一定写入服务端）。
    @Published private(set) var currentUserLiveLocation: LocationPayload?
    /// 名册 membership.id → family_profiles.id（Live 读库种子用）。
    @Published private(set) var profileIdByMembershipId: [UUID: UUID] = [:]

    private let locationStateService: LocationStateDataService
    private let membershipService: HouseholdMembershipDataService

    private var householdId: UUID?
    private var viewHouseholdIds: [UUID] = []
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
            guard selectedMemberIDs.contains(member.id), display.isVisibleOnMap else {
                return nil
            }
            return display
        }
    }

    func listDisplayMember(_ member: UserLocationState) -> UserLocationState {
        displayStateForMap(member)
    }

    func selectPresetHistoryRange(_ kind: LocationHistoryDateRange.Kind) {
        guard kind != .custom else { return }
        historyDateRange.kind = kind
    }

    /// 日期范围内的点数超过当前展示上限（非 VIP 用于引导购买）。
    func exceedsMapHistoryDisplayLimit(displayCount: Int, hasPremium: Bool) -> Bool {
        guard hasPremium == false, isLiveModeActive == false else { return false }
        let cap = PremiumLimits.clampedMapHistoryDisplayCount(displayCount, hasPremium: hasPremium)
        guard LocationMapDisplayPreferences.isUnlimited(cap) == false else { return false }
        return members.contains { member in
            guard selectedMemberIDs.contains(member.id) else { return false }
            let display = displayStateForMap(member)
            return display.isVisibleOnMap && display.locations.count > cap
        }
    }

    /// 本机隐身偏好（不向服务器同步；不受 Live 临时覆盖影响）。
    var isLocationGhostModeEnabled: Bool {
        guard let householdId, let currentProfileId else { return false }
        return LocationGhostPreferences.isEnabled(householdId: householdId, profileId: currentProfileId)
    }

    var isCurrentUserGhost: Bool {
        guard isLiveModeActive == false else { return false }
        return isLocationGhostModeEnabled
    }

    func setLiveModeActive(_ active: Bool) {
        isLiveModeActive = active
    }

    func bind(householdId: UUID?, currentMembershipId: UUID?, currentProfileId: UUID?) {
        self.householdId = householdId
        self.currentMembershipId = currentMembershipId
        self.currentProfileId = currentProfileId
        objectWillChange.send()
    }

    func setViewHouseholdIds(_ ids: [UUID]) {
        viewHouseholdIds = ids
    }

    /// Location 强制单组织：地图与成员列表只展示活动组织。
    func setSingleHouseholdScope(_ householdId: UUID?) {
        self.householdId = householdId
        if let householdId {
            setViewHouseholdIds([householdId])
        } else {
            setViewHouseholdIds([])
        }
    }

    private var effectiveViewHouseholdIds: [UUID] {
        if viewHouseholdIds.isEmpty == false { return viewHouseholdIds }
        if let householdId { return [householdId] }
        return []
    }

    func applyCachedDeviceLocationForMap() {
        guard currentMembershipId != nil else { return }
        guard let cached = LastKnownDeviceLocation.cachedCoordinate() else { return }
        currentUserLiveLocation = LocationPayload(
            latitude: cached.latitude,
            longitude: cached.longitude
        )
        syncCurrentUserBatteryFromDevice()
    }

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
                minDistanceMeters: LocationPersistPreferences.minUpdateDistanceMeters,
                minIntervalSeconds: LocationPersistPreferences.minUpdateIntervalSeconds
            )
        } catch {
            #if DEBUG
            print("[LocationMainViewModel] location report skipped: \(error.localizedDescription)")
            #endif
        }
    }

    func refresh() async {
        let householdIds = effectiveViewHouseholdIds
        guard householdIds.isEmpty == false else {
            members = []
            selectedMemberIDs = []
            currentUserLiveLocation = nil
            return
        }

        if await NetworkMonitor.shared.isConnected == false {
            var offlineMembers: [UserLocationState] = []
            var profileMap: [UUID: UUID] = [:]
            var seen = Set<UUID>()
            for householdId in householdIds {
                if let cachedMembers = await HouseholdLocalCache.loadMembers(for: householdId) {
                    let filtered = cachedMembers.filteredToActiveMembers(in: householdId)
                    let locationRecords = await HouseholdLocalCache.loadLocationStates(for: householdId) ?? []
                    let built = LocationMemberAssembler.buildMembers(
                        roster: HouseholdMemberRoster(
                            profiles: filtered.profiles,
                            memberships: filtered.members
                        ),
                        locationRecords: locationRecords,
                        householdId: householdId,
                        currentMembershipId: currentMembershipId
                    )
                    for member in built where seen.insert(member.id).inserted {
                        offlineMembers.append(member)
                    }
                    for membership in filtered.members {
                        if let profileId = membership.profileId {
                            profileMap[membership.id] = profileId
                        }
                    }
                }
            }
            members = offlineMembers
            profileIdByMembershipId = profileMap
            reconcileSelectionAfterReload()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var mergedMembers: [UserLocationState] = []
            var profileMap: [UUID: UUID] = [:]
            var seen = Set<UUID>()
            for householdId in householdIds {
                let roster = try await membershipService.fetchMemberRoster(in: householdId, activeOnly: false)
                var locationRecords: [LocationStateRecord] = []
                do {
                    locationRecords = try await locationStateService.fetchLocationStates(in: householdId)
                } catch {
                    #if DEBUG
                    print("[LocationMainViewModel] location_states fetch failed: \(error.localizedDescription)")
                    #endif
                }
                for membership in roster.memberships {
                    if let profileId = membership.profileId {
                        profileMap[membership.id] = profileId
                    }
                }
                let built = LocationMemberAssembler.buildMembers(
                    roster: roster,
                    locationRecords: locationRecords,
                    householdId: householdId,
                    currentMembershipId: currentMembershipId
                )
                for member in built where seen.insert(member.id).inserted {
                    mergedMembers.append(member)
                }
                if !locationRecords.isEmpty {
                    HouseholdLocalCache.saveLocationStates(locationRecords, for: householdId)
                }
            }
            profileIdByMembershipId = profileMap
            members = mergedMembers
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
        guard let member = members.first(where: { $0.id == memberID }), member.isSelectableOnMap else { return }
        if selected { selectedMemberIDs.insert(memberID) } else { selectedMemberIDs.remove(memberID) }
    }

    func toggleMemberList() { isMemberListExpanded.toggle() }
    func collapseMemberList() { isMemberListExpanded = false }

    func setLocationGhostMode(_ enabled: Bool) async {
        guard let householdId, let currentProfileId else { return }
        guard isLiveModeActive == false else { return }
        guard isLocationGhostModeEnabled != enabled else { return }

        LocationGhostPreferences.setEnabled(enabled, householdId: householdId, profileId: currentProfileId)
        objectWillChange.send()

        if enabled == false {
            await clearLegacyServerGhostFlagIfNeeded(householdId: householdId, profileId: currentProfileId)
            await captureCurrentUserLocationForMap()
        }
    }

    /// 旧版曾写入服务端 `is_ghost_mode`；关闭本机隐身后顺带清掉，避免 RPC 误拦上报。
    private func clearLegacyServerGhostFlagIfNeeded(householdId: UUID, profileId: UUID) async {
        do {
            let record = try await locationStateService.fetchLocationState(
                householdId: householdId,
                profileId: profileId
            )
            guard record?.isGhostMode == true else { return }
            _ = try await locationStateService.updateGhostMode(
                householdId: householdId,
                profileId: profileId,
                isGhostMode: false
            )
        } catch {
            #if DEBUG
            print("[LocationMainViewModel] clear legacy server ghost skipped: \(error.localizedDescription)")
            #endif
        }
    }

    func syncCurrentUserBatteryFromDevice() {
        guard let currentMembershipId,
              let index = members.firstIndex(where: { $0.id == currentMembershipId && $0.isCurrentUser }) else { return }
        let monitor = DeviceBatteryMonitor.shared
        guard members[index].batteryLevel != monitor.batteryLevel
            || members[index].isCharging != monitor.isCharging else { return }
        members[index].batteryLevel = monitor.batteryLevel
        members[index].isCharging = monitor.isCharging
    }

    private func displayStateForMap(_ member: UserLocationState) -> UserLocationState {
        var updated = member
        if isLiveModeActive {
            if member.isCurrentUser, let live = currentUserLiveLocation {
                updated.currentLocation = live
            }
            if member.isCurrentUser {
                let monitor = DeviceBatteryMonitor.shared
                updated.batteryLevel = monitor.batteryLevel
                updated.isCharging = monitor.isCharging
            }
            updated.isGhostMode = member.isCurrentUser ? false : updated.isGhostMode
            return updated
        }

        let calendar = AppDisplayTimeZone.calendar()
        let now = Date()
        let interval = historyDateRange.interval(now: now, calendar: calendar)
        let includesNow = historyDateRange.includesNow(now, calendar: calendar)
        updated = member.applyingHistoryFilter(interval: interval, includesNow: includesNow)

        if includesNow, member.isCurrentUser, let live = currentUserLiveLocation {
            updated.currentLocation = live
            updated.hasNoPointsInSelectedRange = false
            updated.lastUpdatedAt = live.recordedAt ?? now
        }
        if includesNow, member.isCurrentUser {
            let monitor = DeviceBatteryMonitor.shared
            updated.batteryLevel = monitor.batteryLevel
            updated.isCharging = monitor.isCharging
        }
        return updated
    }

    private func reconcileSelectionAfterReload() {
        let selectableIDs = Set(members.filter(\.isSelectableOnMap).map(\.id))
        let visibleIDs = Set(members.filter(\.isVisibleOnMap).map(\.id))
        let virtualIDs = Set(members.filter(\.isVirtualMember).map(\.id))
        let defaultVisibleIDs = visibleIDs.subtracting(virtualIDs)
        let defaultSelectableIDs = selectableIDs.subtracting(virtualIDs)

        selectedMemberIDs = selectedMemberIDs.intersection(selectableIDs)
        if selectedMemberIDs.isEmpty {
            selectedMemberIDs = defaultVisibleIDs.isEmpty == false ? defaultVisibleIDs : defaultSelectableIDs
        }
    }
}
