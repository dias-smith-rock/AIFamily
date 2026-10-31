import Combine
import CoreLocation
import Foundation
import SwiftUI

@MainActor
final class LocationMainViewModel: ObservableObject {
    @Published private(set) var members: [UserLocationState] = []
    @Published var selectedMemberIDs: Set<UUID> = []
    @Published var isMemberListExpanded = false
    @Published var historyDateRange = LocationHistoryDateRange.today() {
        didSet {
            #if DEBUG
            print(
                "[HistoryRangeTrace] value \(oldValue.kind.rawValue) -> \(historyDateRange.kind.rawValue) "
                    + "vm=\(ObjectIdentifier(self))"
            )
            #endif
        }
    }
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// 本机刚读取的坐标，用于地图展示当前用户（隐身时亦显示，不一定写入服务端）。
    @Published private(set) var currentUserLiveLocation: LocationPayload?
    /// 名册 membership.id → family_profiles.id（Live 读库种子用）。
    @Published private(set) var profileIdByMembershipId: [UUID: UUID] = [:]
    /// `family_profiles.id` → 稀疏轨迹段（近 48h）。
    @Published private(set) var trailSegmentsByProfileId: [UUID: [LocationTrailSegment]] = [:]
    /// `family_profiles.id` → 贴路折线（每段一条）。
    @Published private(set) var roadSnappedRoutesByProfileId: [UUID: [[CLLocationCoordinate2D]]] = [:]

    private let locationStateService: LocationStateDataService
    private let locationTrailService: LocationTrailDataService
    private let membershipService: HouseholdMembershipDataService

    private var householdId: UUID?
    private var viewHouseholdIds: [UUID] = []
    private var currentMembershipId: UUID?
    private var currentProfileId: UUID?
    /// 实时模式期间暂停隐身展示与上报拦截（不改变用户已保存的隐身偏好）。
    private(set) var isLiveModeActive = false
    private var batteryCancellable: AnyCancellable?
    private var roadSnapTask: Task<Void, Never>?
    /// 贴路段数配额（由 Location Tab 注入 VIP 状态）。
    private(set) var roadSnapHasPremiumAccess = false

    init(
        locationStateService: LocationStateDataService,
        locationTrailService: LocationTrailDataService = MockLocationTrailDataService(),
        membershipService: HouseholdMembershipDataService,
        previewMembers: [UserLocationState]? = nil
    ) {
        self.locationStateService = locationStateService
        self.locationTrailService = locationTrailService
        self.membershipService = membershipService
        if let previewMembers {
            members = previewMembers
            configurePreviewRoadSnapDemo(members: previewMembers)
        }
        #if DEBUG
        print("[HistoryRangeTrace] vm init id=\(ObjectIdentifier(self)) kind=\(historyDateRange.kind.rawValue)")
        #endif

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
        #if DEBUG
        print(
            "[HistoryRangeTrace] select preset=\(kind.rawValue) "
                + "household=\(householdId?.uuidString.prefix(8) ?? "nil") "
                + "vm=\(ObjectIdentifier(self))"
        )
        #endif
        historyDateRange.kind = kind
        persistHistoryDateRangeIfNeeded()
    }

    func applyCustomHistoryRange(startDay: Date, endDay: Date) {
        let calendar = AppDisplayTimeZone.calendar()
        let start = calendar.startOfDay(for: min(startDay, endDay))
        let end = calendar.startOfDay(for: max(startDay, endDay))
        historyDateRange = LocationHistoryDateRange(
            kind: .custom,
            customStartDay: start,
            customEndDay: end
        )
        persistHistoryDateRangeIfNeeded()
    }

    /// 进入群组时恢复上次的日期范围；无记录则保持今天。
    func restoreHistoryDateRangeIfNeeded() {
        guard let householdId else {
            #if DEBUG
            print("[HistoryRangeTrace] restore skipped reason=no_household vm=\(ObjectIdentifier(self))")
            #endif
            return
        }
        guard let saved = LocationHistoryDateRangePreferences.load(householdId: householdId) else {
            #if DEBUG
            print(
                "[HistoryRangeTrace] restore skipped reason=no_saved_value "
                    + "household=\(householdId.uuidString.prefix(8)) "
                    + "current=\(historyDateRange.kind.rawValue) vm=\(ObjectIdentifier(self))"
            )
            #endif
            return
        }
        guard saved != historyDateRange else {
            #if DEBUG
            print(
                "[HistoryRangeTrace] restore skipped reason=already_matches "
                    + "kind=\(historyDateRange.kind.rawValue) "
                    + "household=\(householdId.uuidString.prefix(8)) vm=\(ObjectIdentifier(self))"
            )
            #endif
            return
        }
        #if DEBUG
        print(
            "[HistoryRangeTrace] restore apply \(historyDateRange.kind.rawValue) -> \(saved.kind.rawValue) "
                + "household=\(householdId.uuidString.prefix(8)) vm=\(ObjectIdentifier(self))"
        )
        #endif
        historyDateRange = saved
    }

    func setRoadSnapPremiumAccess(_ hasPremium: Bool) {
        guard roadSnapHasPremiumAccess != hasPremium else { return }
        roadSnapHasPremiumAccess = hasPremium
        scheduleRoadSnapRebuild()
    }

    /// 日期筛选变更后重拉轨迹并重建贴路（在线时）。
    func reloadTrailsAndRoadSnapForHistoryChange() async {
        let householdIds = effectiveViewHouseholdIds
        guard householdIds.isEmpty == false else { return }
        guard await NetworkMonitor.shared.isConnected else { return }
        await reloadTrailSegments(for: householdIds)
        scheduleRoadSnapRebuild()
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
        #if DEBUG
        let previous = self.householdId?.uuidString.prefix(8) ?? "nil"
        let next = householdId?.uuidString.prefix(8) ?? "nil"
        print(
            "[HistoryRangeTrace] setScope \(previous) -> \(next) "
                + "kind=\(historyDateRange.kind.rawValue) vm=\(ObjectIdentifier(self))"
        )
        #endif
        self.householdId = householdId
        if let householdId {
            setViewHouseholdIds([householdId])
        } else {
            setViewHouseholdIds([])
        }
        // bind() 会先写入同一个 householdId，不能只在 id 变化时恢复。
        if householdId != nil {
            restoreHistoryDateRangeIfNeeded()
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
            let outcome = try await locationStateService.reportCurrentLocationIfNeeded(
                householdId: householdId,
                profileId: currentProfileId,
                coordinate: payload,
                minDistanceMeters: LocationPersistPreferences.minUpdateDistanceMeters,
                minIntervalSeconds: LocationPersistPreferences.minUpdateIntervalSeconds
            )
            await LocationTrailSegmentRecorder.shared.handlePersistOutcome(
                outcome,
                coordinate: coordinate,
                recordedAt: payload.recordedAt ?? Date()
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

        // 有网也先展示本地缓存，避免地图空白等网。
        if members.isEmpty {
            let cached = await loadCachedMembers(for: householdIds)
            if cached.members.isEmpty == false {
                members = cached.members
                profileIdByMembershipId = cached.profileMap
                reconcileSelectionAfterReload()
            }
        }

        if await NetworkMonitor.shared.isConnected == false {
            let cached = await loadCachedMembers(for: householdIds)
            members = cached.members
            profileIdByMembershipId = cached.profileMap
            trailSegmentsByProfileId = [:]
            roadSnappedRoutesByProfileId = [:]
            reconcileSelectionAfterReload()
            return
        }

        let showBlockingLoad = members.isEmpty
        if showBlockingLoad {
            isLoading = true
            errorMessage = nil
        }
        defer {
            if showBlockingLoad {
                isLoading = false
            }
        }

        do {
            var mergedMembers: [UserLocationState] = []
            var profileMap: [UUID: UUID] = [:]
            var seen = Set<UUID>()
            for householdId in householdIds {
                let roster = try await membershipService.fetchMemberRoster(in: householdId, activeOnly: true)
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
            if members != mergedMembers {
                members = mergedMembers
                reconcileSelectionAfterReload()
            }
            syncCurrentUserBatteryFromDevice()
            await reloadTrailSegments(for: householdIds)
            scheduleRoadSnapRebuild()
        } catch {
            if members.isEmpty {
                members = []
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadCachedMembers(
        for householdIds: [UUID]
    ) async -> (members: [UserLocationState], profileMap: [UUID: UUID]) {
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
        return (offlineMembers, profileMap)
    }

    private func reloadTrailSegments(for householdIds: [UUID]) async {
        let calendar = AppDisplayTimeZone.calendar()
        let interval = historyDateRange.interval(calendar: calendar)
        let since = LocationTrailSegmentFilter.trailFetchCutoff(for: historyDateRange, calendar: calendar)

        var merged: [UUID: [LocationTrailSegment]] = [:]
        var trailFetchFailed = false
        for householdId in householdIds {
            do {
                let segments = try await locationTrailService.fetchTrailSegments(in: householdId, since: since)
                for segment in segments {
                    merged[segment.entityId, default: []].append(segment)
                }
                #if DEBUG
                let profileCount = Set(segments.map(\.entityId)).count
                print(
                    "[RoadSnapTrace] trail fetch ok household=\(householdId.uuidString.prefix(8)) "
                        + "since=\(Self.roadSnapTraceStamp(since)) segments=\(segments.count) profiles=\(profileCount)"
                )
                #endif
            } catch {
                trailFetchFailed = true
                #if DEBUG
                print("[LocationMainViewModel] trail fetch failed: \(error.localizedDescription)")
                print(
                    "[RoadSnapTrace] trail fetch failed household=\(householdId.uuidString.prefix(8)) "
                        + "since=\(Self.roadSnapTraceStamp(since)) error=\(error.localizedDescription)"
                )
                #endif
            }
        }
        for key in merged.keys {
            let filtered = LocationTrailSegmentFilter.segments(merged[key] ?? [], intersecting: interval)
            merged[key] = filtered.sorted { $0.endedAt > $1.endedAt }
        }
        trailSegmentsByProfileId = merged
        #if DEBUG
        if trailFetchFailed {
            print("[LocationRoadSnap] skip demo segments because trail fetch failed")
            print("[RoadSnapTrace] demo inject skipped reason=trail_fetch_failed")
        } else {
            applyRoadSnapDemoSegmentsIfEnabled()
        }
        let stored = trailSegmentsByProfileId.map { "\($0.key.uuidString.prefix(8)):\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
        print(
            "[RoadSnapTrace] trail stored range=\(historyDateRange.kind) "
                + "profiles=[\(stored.isEmpty ? "none" : stored)]"
        )
        #endif
    }

    private func filteredTrailSegments(forProfileId profileId: UUID) -> [LocationTrailSegment] {
        let raw = trailSegmentsByProfileId[profileId] ?? []
        return LocationTrailSegmentMerger.mergeConnectable(raw)
    }

    private func scheduleRoadSnapRebuild() {
        roadSnapTask?.cancel()
        roadSnapTask = Task { [weak self] in
            await self?.rebuildRoadSnappedRoutes()
        }
    }

    /// 地图展示点数变化后，用同样的历史点重做贴路。
    func scheduleRoadSnapRebuildFromDisplayCountChange() {
        scheduleRoadSnapRebuild()
    }

    private func rebuildRoadSnappedRoutes() async {
        let selectedProfileIDs: Set<UUID> = Set(
            selectedMemberIDs.compactMap { profileIdByMembershipId[$0] }
        )
        let segmentCap = LocationRoadSnapPreferences.maxSegmentsPerMember(
            hasPremium: roadSnapHasPremiumAccess
        )

        var next: [UUID: [[CLLocationCoordinate2D]]] = [:]
        for profileId in selectedProfileIDs {
            let trailSegments = filteredTrailSegments(forProfileId: profileId)
            let segmentsToSnap = snapCandidates(
                profileId: profileId,
                trailSegments: trailSegments,
                segmentCap: segmentCap
            )
            var routes: [[CLLocationCoordinate2D]] = []
            for segment in segmentsToSnap {
                if Task.isCancelled { return }
                let anchors = segment.waypoints.count
                let coords = await RoadSnapRouteBuilder.shared.roadCoordinates(for: segment)
                #if DEBUG
                let geometry = coords.count > anchors ? "road_vertices" : "anchors_only"
                print(
                    "[RoadSnapTrace] drawn profile=\(profileId.uuidString.prefix(8)) "
                        + "segment=\(segment.id.uuidString.prefix(8)) anchors=\(anchors) "
                        + "points=\(coords.count) geometry=\(geometry)"
                )
                #endif
                if coords.count >= 2 {
                    routes.append(coords)
                }
            }
            if routes.isEmpty == false {
                next[profileId] = routes
            }
            #if DEBUG
            let draw = routes.isEmpty ? "breadcrumb_straight" : "road_snap_layer"
            let pointList = routes.map { String($0.count) }.joined(separator: ",")
            print(
                "[RoadSnapTrace] publish profile=\(profileId.uuidString.prefix(8)) "
                    + "draw=\(draw) routes=\(routes.count) points=[\(pointList)]"
            )
            #endif
        }

        guard Task.isCancelled == false else { return }
        roadSnappedRoutesByProfileId = next
    }

    /// 贴路候选：近 48h 轨迹段 + 日期范围内未被轨迹段覆盖的历史位置点（几天前只有 `location_states` 稀疏点）。
    private func snapCandidates(
        profileId: UUID,
        trailSegments: [LocationTrailSegment],
        segmentCap: Int
    ) -> [LocationTrailSegment] {
        let breadcrumbs = historyBreadcrumbSegments(
            profileId: profileId,
            coveredBy: trailSegments
        )
        let trailSlots = max(0, segmentCap - min(breadcrumbs.count, segmentCap))
        let trails = Array(trailSegments.prefix(trailSlots))
        #if DEBUG
        let breadcrumbPoints = breadcrumbs.map { String($0.waypoints.count) }.joined(separator: ",")
        let trailPoints = trails.map { String($0.waypoints.count) }.joined(separator: ",")
        print(
            "[RoadSnapTrace] candidates profile=\(profileId.uuidString.prefix(8)) "
                + "cap=\(segmentCap) breadcrumb=\(breadcrumbs.count)[\(breadcrumbPoints)] "
                + "trail=\(trails.count)[\(trailPoints)] trailAvailable=\(trailSegments.count)"
        )
        #endif
        // 稀疏历史点优先占用每成员段数名额，避免近 48h 密轨迹占满名额后，几天前的折线没有贴路机会。
        return breadcrumbs + trails
    }

    /// 把日期筛选内、且不落在任何轨迹段时间窗里的位置点，按时间切成可贴路的段。
    private func historyBreadcrumbSegments(
        profileId: UUID,
        coveredBy trailSegments: [LocationTrailSegment]
    ) -> [LocationTrailSegment] {
        guard let membershipId = profileIdByMembershipId.first(where: { $0.value == profileId })?.key,
              let member = members.first(where: { $0.id == membershipId }) else {
            return []
        }

        let display = displayStateForMap(member)
        let displayCount = PremiumLimits.clampedMapHistoryDisplayCount(
            LocationMapDisplayPreferences.historyDisplayCount,
            hasPremium: roadSnapHasPremiumAccess
        )
        let visible = display.mapVisibleLocations(displayCount: displayCount)
        let chronological = Array(visible.reversed())
        guard chronological.count >= 2 else { return [] }

        var runs: [[LocationPayload]] = []
        var current: [LocationPayload] = []
        for payload in chronological {
            if isCoveredByTrail(payload, trailSegments: trailSegments) {
                if current.count >= 2 {
                    runs.append(current)
                }
                current = []
            } else {
                current.append(payload)
            }
        }
        if current.count >= 2 {
            runs.append(current)
        }

        return runs.compactMap { run in
            let waypoints = run.map {
                TrailWaypoint(latitude: $0.latitude, longitude: $0.longitude, recordedAt: $0.recordedAt)
            }
            guard waypoints.count >= 2 else { return nil }
            let startedAt = run.first?.recordedAt ?? Date.distantPast
            let endedAt = run.last?.recordedAt ?? startedAt
            return LocationTrailSegment(
                id: Self.stableBreadcrumbSegmentId(profileId: profileId, waypoints: waypoints),
                householdId: member.householdId,
                entityId: profileId,
                startedAt: startedAt,
                endedAt: max(endedAt, startedAt),
                waypoints: waypoints
            )
        }
    }

    private func isCoveredByTrail(_ payload: LocationPayload, trailSegments: [LocationTrailSegment]) -> Bool {
        guard let stamp = payload.recordedAt else { return false }
        return trailSegments.contains { segment in
            stamp >= segment.startedAt && stamp <= segment.endedAt
        }
    }

    private static func roadSnapTraceStamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// 进程内稳定，便于 Directions 磁盘缓存命中。
    private static func stableBreadcrumbSegmentId(profileId: UUID, waypoints: [TrailWaypoint]) -> UUID {
        var hash: UInt64 = 14_695_981_039_346_656_037
        func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        for byte in profileId.uuidString.utf8 {
            mix(byte)
        }
        for point in waypoints {
            let token = String(format: "%.4f,%.4f", point.latitude, point.longitude)
            for byte in token.utf8 {
                mix(byte)
            }
        }
        var bytes = withUnsafeBytes(of: hash.littleEndian) { Array($0) }
        while bytes.count < 16 {
            bytes.append(0)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func isSelected(memberID: UUID) -> Bool {
        selectedMemberIDs.contains(memberID)
    }

    func setSelected(_ selected: Bool, for memberID: UUID) {
        guard let member = members.first(where: { $0.id == memberID }), member.isSelectableOnMap else { return }
        if selected { selectedMemberIDs.insert(memberID) } else { selectedMemberIDs.remove(memberID) }
        persistMemberSelectionIfNeeded()
        scheduleRoadSnapRebuild()
    }

    private func persistMemberSelectionIfNeeded() {
        guard let householdId else { return }
        LocationMapMemberSelectionPreferences.save(selectedMemberIDs, householdId: householdId)
    }

    private func persistHistoryDateRangeIfNeeded() {
        guard let householdId else {
            #if DEBUG
            print(
                "[HistoryRangeTrace] save skipped reason=no_household "
                    + "kind=\(historyDateRange.kind.rawValue) vm=\(ObjectIdentifier(self))"
            )
            #endif
            return
        }
        LocationHistoryDateRangePreferences.save(historyDateRange, householdId: householdId)
        #if DEBUG
        print(
            "[HistoryRangeTrace] save household=\(householdId.uuidString.prefix(8)) "
                + "kind=\(historyDateRange.kind.rawValue) vm=\(ObjectIdentifier(self))"
        )
        #endif
    }

    /// 选中成员对应的贴路折线；无轨迹段时返回空。
    func roadSnappedRoutes(forMembershipId membershipId: UUID) -> [[CLLocationCoordinate2D]] {
        guard let profileId = profileIdByMembershipId[membershipId] else { return [] }
        return roadSnappedRoutesByProfileId[profileId] ?? []
    }

    /// 贴路展示用起终点：与 `MapPolyline` 一致（最新段终点 = 终点，最早段折线起点 = 起点）。
    func roadSnapDisplayEndpoints(forMembershipId membershipId: UUID) -> (
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    )? {
        let routes = roadSnappedRoutes(forMembershipId: membershipId)
        if let newestRoute = routes.first,
           let oldestRoute = routes.last,
           let end = newestRoute.last,
           let start = oldestRoute.first,
           newestRoute.count >= 2,
           oldestRoute.count >= 2 {
            return (start, end)
        }

        guard let profileId = profileIdByMembershipId[membershipId] else { return nil }
        let segments = filteredTrailSegments(forProfileId: profileId)
        guard let newest = segments.first, let oldest = segments.last else { return nil }
        guard let end = newest.waypoints.last?.coordinate,
              let start = oldest.waypoints.first?.coordinate else {
            return nil
        }
        return (start, end)
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

    /// SwiftUI Preview：绑定 household、profile 映射并拉取 Mock 轨迹。
    func configurePreviewRoadSnapDemo(members: [UserLocationState]) {
        let householdId = UserLocationState.previewHouseholdId
        setSingleHouseholdScope(householdId)
        var profileMap: [UUID: UUID] = [:]
        for member in members {
            profileMap[member.id] = member.id
        }
        profileIdByMembershipId = profileMap
        if let current = members.first(where: \.isCurrentUser) {
            currentMembershipId = current.id
            currentProfileId = current.id
            selectedMemberIDs = [current.id]
        }
        roadSnapHasPremiumAccess = true
        Task {
            await reloadTrailSegments(for: [householdId])
            scheduleRoadSnapRebuild()
        }
    }

    #if DEBUG
    private func applyRoadSnapDemoSegmentsIfEnabled() {
        guard LocationRoadSnapDemoData.injectWhenTrailEmpty else { return }
        guard let householdId = householdId ?? effectiveViewHouseholdIds.first else { return }

        let profileId: UUID? = {
            if let currentProfileId { return currentProfileId }
            if let currentMembershipId { return profileIdByMembershipId[currentMembershipId] }
            return members.first(where: \.isCurrentUser).flatMap { profileIdByMembershipId[$0.id] ?? $0.id }
        }()
        guard let profileId else { return }

        let existing = trailSegmentsByProfileId[profileId] ?? []
        guard existing.isEmpty else { return }

        let anchor = members.first(where: { profileIdByMembershipId[$0.id] == profileId || $0.id == profileId })?
            .currentLocation?.coordinate
            ?? currentUserLiveLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 22.2819, longitude: 114.158)

        let demo = LocationRoadSnapDemoData.makeSegments(
            householdId: householdId,
            profileId: profileId,
            anchor: anchor
        )
        guard demo.isEmpty == false else { return }
        trailSegmentsByProfileId[profileId] = demo
        print("[LocationRoadSnap] injected demo segments count=\(demo.count) profile=\(profileId.uuidString.prefix(8))")
        print("[RoadSnapTrace] demo inject count=\(demo.count) profile=\(profileId.uuidString.prefix(8))")
        scheduleRoadSnapRebuild()
    }
    #endif

    private func reconcileSelectionAfterReload() {
        let selectableIDs = Set(members.filter(\.isSelectableOnMap).map(\.id))
        selectedMemberIDs = selectedMemberIDs.intersection(selectableIDs)

        if selectedMemberIDs.isEmpty, let householdId {
            if let saved = LocationMapMemberSelectionPreferences.load(householdId: householdId) {
                selectedMemberIDs = saved.intersection(selectableIDs)
            }
        }

        if selectedMemberIDs.isEmpty {
            if let currentMembershipId, selectableIDs.contains(currentMembershipId) {
                selectedMemberIDs = [currentMembershipId]
                if let householdId {
                    LocationMapMemberSelectionPreferences.save(selectedMemberIDs, householdId: householdId)
                }
            } else {
                let visibleIDs = Set(members.filter(\.isVisibleOnMap).map(\.id))
                let virtualIDs = Set(members.filter(\.isVirtualMember).map(\.id))
                let defaultVisibleIDs = visibleIDs.subtracting(virtualIDs)
                let defaultSelectableIDs = selectableIDs.subtracting(virtualIDs)
                selectedMemberIDs = defaultVisibleIDs.isEmpty == false ? defaultVisibleIDs : defaultSelectableIDs
            }
        }
    }
}
