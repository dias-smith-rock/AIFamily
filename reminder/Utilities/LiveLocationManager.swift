import Combine
import CoreLocation
import Foundation

#if canImport(Supabase)
import Supabase
#endif

/// 群组 Live Huddle：Presence 管理房间生命周期 + Broadcast 秒级位置双轨引擎。
@MainActor
final class LiveLocationManager: NSObject, ObservableObject {
    static let inactivityTimeoutSeconds = 900
    private static let movementResetsInactivityMeters: Double = 8
    private static let peerMoveMinInterval: TimeInterval = 1.0
    /// 退出 Live 后抑制迟到的 presence_state / peer_move 把该成员又加回地图。
    private static let departedSuppressionSeconds: TimeInterval = 45

    @Published private(set) var isLiveModeActive = false
    /// 当前 Huddle 内活跃成员的 **membership id**（来自 Presence，非数据库）。
    @Published private(set) var activeParticipants: [UUID] = []
    @Published private(set) var livePeerLocations: [UUID: CLLocationCoordinate2D] = [:]
    @Published private(set) var livePeerLocationUpdatedAt: [UUID: Date] = [:]
    /// 本机指南针朝向（真北顺时针角度）；仅 Live 模式有效。
    @Published private(set) var currentHeadingDegrees: Double?
    @Published private(set) var livePeerHeadings: [UUID: Double] = [:]
    @Published private(set) var livePeerBattery: [UUID: LivePeerBatteryState] = [:]
    @Published var showInactivityEndedNotice = false

    private let locationStateService: LocationStateDataService
    private let batteryMonitor = DeviceBatteryMonitor.shared
    private let locationManager = CLLocationManager()

    private var householdId: UUID?
    private var currentMembershipId: UUID?
    /// `location_states.entity_id`（family_profiles.id）。
    private var currentProfileId: UUID?
    private var profileIdByMembershipId: [UUID: UUID] = [:]
    private var currentUserId: UUID?
    private var currentDisplayName: String = "群组成员"
    private var connectedChannelHouseholdId: UUID?
    private var pendingPresenceTrack = false
    private var householdTransitionTask: Task<Void, Never>?

    private var participantSet: Set<UUID> = []
    private var inactivitySecondsRemaining = inactivityTimeoutSeconds
    private var lastMovementAnchor: CLLocation?

    private var inactivityCancellable: AnyCancellable?
    private var batteryCancellable: AnyCancellable?
    private var receiveTask: Task<Void, Never>?
    private var receiveSyncRequestTask: Task<Void, Never>?
    private var receivePeerLeftTask: Task<Void, Never>?

    #if canImport(Supabase)
    private var liveChannel: RealtimeChannelV2?
    private var presenceSubscription: RealtimeSubscription?
    #endif

    private var lastLiveBroadcastLocation: CLLocation?
    private var lastPeerMoveSentAt: Date?
    private var lastPresenceRefreshAt: Date?
    private var lastSelfLeaveRetrackAt: Date?
    private var isChannelSubscribed = false
    private var channelReconnectTask: Task<Void, Never>?
    private var recentlyDepartedMembershipIds: [UUID: Date] = [:]

    #if DEBUG
    private func liveLog(_ message: String) {
        print("[LiveLocationManager] \(message)")
    }
    #else
    private func liveLog(_ message: String) {}
    #endif

    init(locationStateService: LocationStateDataService) {
        self.locationStateService = locationStateService
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100

        batteryCancellable = batteryMonitor.$batteryLevel
            .combineLatest(batteryMonitor.$isCharging)
            .sink { [weak self] _, _ in
                Task { @MainActor in
                    await self?.broadcastBatteryOrLocationUpdate()
                }
            }
    }

    /// 地图 / 列表展示用：本机读 `DeviceBatteryMonitor`，对方读最近广播。
    func batteryDisplay(
        for membershipId: UUID,
        rosterFallback: UserLocationState?
    ) -> (level: Int, isCharging: Bool) {
        if membershipId == currentMembershipId {
            return (batteryMonitor.batteryLevel, batteryMonitor.isCharging)
        }
        if let peer = livePeerBattery[membershipId] {
            return (peer.clampedLevel, peer.isCharging)
        }
        if let rosterFallback {
            return (rosterFallback.clampedBatteryLevel, rosterFallback.isCharging)
        }
        return (100, false)
    }

    /// 地图标注轮播用：Live 优先取最近一次坐标更新时间，否则回落到 `location_states.updated_at`。
    func locationUpdatedAt(for membershipId: UUID, rosterFallback: UserLocationState?) -> Date? {
        if let live = livePeerLocationUpdatedAt[membershipId] {
            return live
        }
        return rosterFallback?.currentLocationUpdatedAt
    }

    var isHuddleActive: Bool {
        activeParticipants.isEmpty == false
    }

    var isCurrentUserInsideHuddle: Bool {
        guard let currentMembershipId else { return false }
        return isLiveModeActive || activeParticipants.contains(currentMembershipId)
    }

    func bind(
        householdId: UUID?,
        currentMembershipId: UUID?,
        currentProfileId: UUID?,
        currentUserId: UUID?,
        displayName: String? = nil
    ) {
        let householdChanged = self.householdId != householdId
        self.householdId = householdId
        self.currentMembershipId = currentMembershipId
        self.currentProfileId = currentProfileId
        self.currentUserId = currentUserId
        if let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           trimmed.isEmpty == false {
            currentDisplayName = trimmed
        }

        if householdChanged {
            profileIdByMembershipId = [:]
            householdTransitionTask?.cancel()
            householdTransitionTask = Task { @MainActor in
                if isLiveModeActive {
                    await leaveLiveSession(silent: true)
                }
                await disconnectChannel()
            }
        }
    }

    /// 名册刷新后更新 membership → profile，供 Live 从 `location_states` 占位种子。
    func updateProfileIdByMembershipId(_ map: [UUID: UUID]) {
        profileIdByMembershipId = map
    }

    /// 被动订阅 Presence，用于 Lobby 卡片展示（不 track、不开启高精度 GPS）。
    func observeHuddleLobby() async {
        guard await NetworkMonitor.shared.isConnected else {
            liveLog("observeHuddleLobby skipped: offline")
            return
        }
        guard isLiveModeActive == false else {
            liveLog("observeHuddleLobby skipped: live mode active")
            return
        }
        for attempt in 1...3 {
            await ensureChannelConnected(shouldTrack: false, subscribeAttempt: 0)
            if isChannelSubscribed { return }
            if Task.isCancelled { return }
            guard attempt < 3 else { break }
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
        }
    }

    /// 加入 Live Huddle：track Presence + 高精度 GPS + 广播位置。
    func startLiveSession() async {
        guard isLiveModeActive == false else { return }
        guard currentMembershipId != nil, currentUserId != nil else { return }

        isLiveModeActive = true
        // 仅清空坐标缓存；保留 `participantSet`（Lobby / 已有 presence_diff），避免已订阅频道上丢失在场成员。
        livePeerLocations = [:]
        livePeerLocationUpdatedAt = [:]
        livePeerHeadings = [:]
        livePeerBattery = [:]
        currentHeadingDegrees = nil
        showInactivityEndedNotice = false
        batteryMonitor.refresh()
        lastMovementAnchor = nil
        resetInactivityTimer()
        seedLocalLiveLocationFromCache()

        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        await ensureChannelConnected(shouldTrack: true)

        if hasRemoteParticipants() == false {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        applyActiveParticipants(participantSet)

        if let location = currentLocationForPresence() {
            recordLocalLiveLocation(location)
        } else {
            seedLocalLiveLocationFromCache()
        }

        await requestPeerLocationSync()
        await rebroadcastLocationToPeers()

        liveLog(
            "startLiveSession ready: participants=\(activeParticipants.count) "
                + "peerLocations=\(livePeerLocations.count) liveActive=\(isLiveModeActive)"
        )
        startInactivityWatchdog()
    }

    /// 离开 Huddle：untrack Presence；若为房间内最后一人则 unsubscribe 并移除 Realtime 频道。
    func leaveLiveSession(silent: Bool = false) async {
        guard isLiveModeActive else { return }

        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100
        currentHeadingDegrees = nil
        lastLiveBroadcastLocation = nil

        inactivityCancellable?.cancel()
        inactivityCancellable = nil

        let shouldCloseChannel = isOnlyParticipantInRoom()

        #if canImport(Supabase)
        if let currentMembershipId {
            await broadcastPeerLeft(membershipId: currentMembershipId)
        }
        if let channel = liveChannel {
            await channel.untrack()
        }
        #endif

        if let currentLocation = locationManager.location {
            await uploadToDatabaseIfNeeded(currentLocation, force: true)
        }

        isLiveModeActive = false
        pendingPresenceTrack = false
        livePeerLocations = [:]
        livePeerLocationUpdatedAt = [:]
        livePeerHeadings = [:]
        livePeerBattery = [:]

        if shouldCloseChannel {
            participantSet = []
            activeParticipants = []
            await disconnectChannel()
            liveLog("live channel closed: last participant left live mode")
        }

        if silent == false, inactivitySecondsRemaining <= 0 {
            showInactivityEndedNotice = true
        }
    }

    func dismissInactivityNotice() {
        showInactivityEndedNotice = false
    }

    func recordUserInteraction() {
        guard isLiveModeActive else { return }
        resetInactivityTimer()
    }

    // MARK: - Channel

    private func liveHuddleTopic(for householdId: UUID) -> String {
        "circle:\(householdId.uuidString.lowercased()):live_huddle"
    }

    private func awaitHouseholdTransitionIfNeeded() async {
        guard let task = householdTransitionTask else { return }
        await task.value
        householdTransitionTask = nil
    }

    private func ensureChannelConnected(shouldTrack: Bool, subscribeAttempt: Int = 0) async {
        #if canImport(Supabase)
        await awaitHouseholdTransitionIfNeeded()

        guard let householdId else {
            #if DEBUG
            print("[LiveLocationManager] skip channel connect: householdId is nil")
            #endif
            return
        }

        pendingPresenceTrack = pendingPresenceTrack || shouldTrack

        if let connectedChannelHouseholdId, connectedChannelHouseholdId != householdId {
            #if DEBUG
            print(
                "[LiveLocationManager] household changed \(connectedChannelHouseholdId.uuidString.prefix(8))"
                    + " → \(householdId.uuidString.prefix(8)), reconnecting channel"
            )
            #endif
            await disconnectChannel()
        }

        let topic = liveHuddleTopic(for: householdId)

        if liveChannel == nil {
            let channel = SupabaseManager.shared.client.realtimeV2.channel(topic) { config in
                config.isPrivate = true
            }
            liveChannel = channel
            connectedChannelHouseholdId = householdId

            presenceSubscription?.cancel()
            presenceSubscription = channel.onPresenceChange { [weak self] presence in
                Task { @MainActor in
                    self?.handlePresenceChange(presence)
                }
            }

            do {
                try await channel.subscribeWithError()
                guard liveChannel === channel else { return }
                isChannelSubscribed = channel.status == .subscribed
                liveLog("subscribed topic=\(topic) status=\(channel.status)")
                startPeerMoveBroadcastReceiver(on: channel)
                startPeerSyncRequestReceiver(on: channel)
                startPeerLeftBroadcastReceiver(on: channel)
                await trackPresenceIfNeeded(on: channel)
            } catch is CancellationError {
                await abandonChannel(channel)
                guard Task.isCancelled == false, subscribeAttempt < 1 else {
                    #if DEBUG
                    print("⚠️ [LiveLocationManager] subscribe cancelled topic=\(topic)")
                    #endif
                    return
                }
                #if DEBUG
                print("⚠️ [LiveLocationManager] subscribe cancelled, retrying topic=\(topic)")
                #endif
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard Task.isCancelled == false else { return }
                await ensureChannelConnected(shouldTrack: shouldTrack, subscribeAttempt: subscribeAttempt + 1)
            } catch {
                await abandonChannel(channel)
                print("❌ [Realtime Error] subscribe failed topic=\(topic): \(error)")
            }
        } else if isLiveChannelReady() {
            isChannelSubscribed = true
            if let channel = liveChannel {
                startPeerMoveBroadcastReceiver(on: channel)
                startPeerSyncRequestReceiver(on: channel)
                startPeerLeftBroadcastReceiver(on: channel)
            }
            await trackPresenceIfNeeded(on: liveChannel)
        } else if liveChannel?.status == .subscribing {
            if await waitForChannelSubscribed(timeoutSeconds: 8) {
                if let channel = liveChannel {
                    startPeerMoveBroadcastReceiver(on: channel)
                    startPeerSyncRequestReceiver(on: channel)
                    startPeerLeftBroadcastReceiver(on: channel)
                }
                await trackPresenceIfNeeded(on: liveChannel)
            } else {
                liveLog("subscribe wait timed out topic=\(topic)")
            }
        } else if isLiveModeActive {
            liveLog("channel lost during live — scheduling reconnect")
            await scheduleChannelReconnect()
        } else {
            await disconnectChannel()
        }
        #endif
    }

    private func isLiveChannelReady() -> Bool {
        #if canImport(Supabase)
        guard let channel = liveChannel else { return false }
        return channel.status == .subscribed
        #else
        return false
        #endif
    }

    @discardableResult
    private func ensureLiveChannelReady() async -> Bool {
        #if canImport(Supabase)
        if isLiveChannelReady() {
            isChannelSubscribed = true
            return true
        }
        if liveChannel?.status == .subscribing {
            let ready = await waitForChannelSubscribed(timeoutSeconds: 6)
            isChannelSubscribed = ready
            return ready
        }
        liveLog(
            "channel not ready status=\(String(describing: liveChannel?.status)) "
                + "liveActive=\(isLiveModeActive)"
        )
        if isLiveModeActive {
            await scheduleChannelReconnect()
        } else {
            await ensureChannelConnected(shouldTrack: pendingPresenceTrack)
        }
        let ready = isLiveChannelReady()
        isChannelSubscribed = ready
        return ready
        #else
        return false
        #endif
    }

    #if canImport(Supabase)
    private func waitForChannelSubscribed(timeoutSeconds: TimeInterval) async -> Bool {
        guard let channel = liveChannel else { return false }
        if channel.status == .subscribed {
            isChannelSubscribed = true
            return true
        }
        guard channel.status == .subscribing else { return false }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                for await status in channel.statusChange {
                    if status == .subscribed {
                        return true
                    }
                    if status == .unsubscribed || status == .unsubscribing {
                        return false
                    }
                }
                return channel.status == .subscribed
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return false
            }
            let ready = await group.next() ?? false
            group.cancelAll()
            if ready {
                isChannelSubscribed = true
            }
            return ready
        }
    }
    #endif

    private func scheduleChannelReconnect() async {
        if let existing = channelReconnectTask {
            await existing.value
            return
        }
        let task = Task { @MainActor in
            defer { channelReconnectTask = nil }
            await reconnectChannelForLiveSession()
        }
        channelReconnectTask = task
        await task.value
    }

    private func reconnectChannelForLiveSession() async {
        liveLog("reconnectChannelForLiveSession preserve peer cache")
        pendingPresenceTrack = true
        await disconnectChannel(preserveLiveState: true)
        await ensureChannelConnected(shouldTrack: true)
    }

    private func hasRemoteParticipants() -> Bool {
        guard let currentMembershipId else { return false }
        return participantSet.contains { $0 != currentMembershipId }
    }

    private func seedLocalLiveLocationFromCache() {
        guard let currentMembershipId, isLiveModeActive else { return }
        guard livePeerLocations[currentMembershipId] == nil else { return }
        guard let cached = LastKnownDeviceLocation.cachedCoordinate() else { return }
        setLivePeerLocation(cached, for: currentMembershipId)
        livePeerBattery[currentMembershipId] = LivePeerBatteryState(
            level: batteryMonitor.batteryLevel,
            isCharging: batteryMonitor.isCharging
        )
        liveLog("seeded local live coords from device cache")
    }

    private func ensurePresenceTracked() async {
        pendingPresenceTrack = true
        guard await ensureLiveChannelReady() else { return }
        await trackPresenceIfNeeded(on: liveChannel)
    }

    #if canImport(Supabase)
    private func abandonChannel(_ channel: RealtimeChannelV2) async {
        receiveTask?.cancel()
        receiveTask = nil
        receiveSyncRequestTask?.cancel()
        receiveSyncRequestTask = nil
        receivePeerLeftTask?.cancel()
        receivePeerLeftTask = nil
        presenceSubscription?.cancel()
        presenceSubscription = nil
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
        if liveChannel === channel {
            liveChannel = nil
            connectedChannelHouseholdId = nil
        }
        isChannelSubscribed = false
    }
    #endif

    #if canImport(Supabase)
    private func currentLocationForPresence() -> CLLocation? {
        lastLiveBroadcastLocation ?? locationManager.location
    }

    private func makePresencePayload(includeLocation: Bool) -> LiveHuddlePresencePayload? {
        guard let currentUserId, let currentMembershipId else { return nil }
        let location = includeLocation ? currentLocationForPresence() : nil
        return LiveHuddlePresencePayload(
            userId: currentUserId,
            displayName: currentDisplayName,
            membershipId: currentMembershipId,
            lat: location?.coordinate.latitude,
            lng: location?.coordinate.longitude,
            headingDegrees: currentHeadingDegrees,
            batteryLevel: batteryMonitor.batteryLevel,
            isCharging: batteryMonitor.isCharging
        )
    }

    private func trackPresenceIfNeeded(on channel: RealtimeChannelV2?) async {
        guard pendingPresenceTrack, let channel else { return }
        guard channel.status == .subscribed else {
            liveLog("track skipped: channel status=\(channel.status)")
            return
        }
        isChannelSubscribed = true
        guard let payload = makePresencePayload(includeLocation: true) else {
            liveLog("track skipped: missing user/membership context")
            return
        }

        do {
            try await channel.track(payload)
            pendingPresenceTrack = false
            lastPresenceRefreshAt = Date()
            liveLog(
                "track user_id=\(payload.userId.prefix(8)) name=\(payload.name) "
                    + "membership=\(payload.membershipId.prefix(8)) "
                    + "coord=\(payload.hasCoordinate ? "yes" : "no")"
            )
        } catch {
            print("❌ [Realtime Error] track failed: \(error)")
        }
    }

    #endif

    /// 当前 Presence 房间内是否仅剩本机（含仅自己一人 tracked 的情况）。
    private func isOnlyParticipantInRoom() -> Bool {
        guard let currentMembershipId else {
            return participantSet.isEmpty
        }
        return participantSet.allSatisfy { $0 == currentMembershipId }
    }

    private func disconnectChannel(preserveLiveState: Bool = false) async {
        channelReconnectTask?.cancel()
        channelReconnectTask = nil
        inactivityCancellable?.cancel()
        inactivityCancellable = nil
        receiveTask?.cancel()
        receiveTask = nil
        receiveSyncRequestTask?.cancel()
        receiveSyncRequestTask = nil
        receivePeerLeftTask?.cancel()
        receivePeerLeftTask = nil

        #if canImport(Supabase)
        presenceSubscription?.cancel()
        presenceSubscription = nil

        if let channel = liveChannel {
            let topic = channel.topic
            if channel.status == .subscribed || channel.status == .subscribing {
                await channel.unsubscribe()
                liveLog("live channel unsubscribed topic=\(topic)")
            }
            await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
            liveLog("live channel removed topic=\(topic)")
        }
        liveChannel = nil
        connectedChannelHouseholdId = nil
        pendingPresenceTrack = false
        householdTransitionTask = nil
        #endif

        isChannelSubscribed = false
        if preserveLiveState == false {
            participantSet = []
            activeParticipants = []
            livePeerLocations = [:]
            livePeerLocationUpdatedAt = [:]
            livePeerHeadings = [:]
            livePeerBattery = [:]
            currentHeadingDegrees = nil
            lastLiveBroadcastLocation = nil
            recentlyDepartedMembershipIds = [:]
        }
    }

    private func broadcastBatteryOrLocationUpdate() async {
        guard isLiveModeActive else { return }
        if let location = lastLiveBroadcastLocation ?? locationManager.location {
            await sendLiveBroadcast(location)
        }
    }

    #if canImport(Supabase)
    private func startPeerMoveBroadcastReceiver(on channel: RealtimeChannelV2) {
        receiveTask?.cancel()
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await message in channel.broadcastStream(event: "peer_move") {
                guard !Task.isCancelled else { break }
                handlePeerMoveBroadcast(message)
            }
        }
    }

    private func startPeerSyncRequestReceiver(on channel: RealtimeChannelV2) {
        receiveSyncRequestTask?.cancel()
        receiveSyncRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await message in channel.broadcastStream(event: "peer_sync_request") {
                guard !Task.isCancelled else { break }
                handlePeerSyncRequest(message)
            }
        }
    }

    private func startPeerLeftBroadcastReceiver(on channel: RealtimeChannelV2) {
        receivePeerLeftTask?.cancel()
        receivePeerLeftTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await message in channel.broadcastStream(event: "peer_left") {
                guard !Task.isCancelled else { break }
                handlePeerLeftBroadcast(message)
            }
        }
    }

    private struct PeerSyncRequestPayload: Codable, Sendable {
        let membershipId: UUID
    }

    private struct PeerLeftPayload: Codable, Sendable {
        let membershipId: UUID
    }

    private func broadcastPeerLeft(membershipId: UUID) async {
        guard let channel = liveChannel, channel.status == .subscribed else {
            liveLog("peer_left skipped: channel unavailable")
            return
        }
        let payload = PeerLeftPayload(membershipId: membershipId)
        do {
            try await channel.broadcast(event: "peer_left", message: payload)
            liveLog("peer_left sent membership=\(membershipId.uuidString.prefix(8))")
        } catch {
            liveLog("peer_left failed: \(error.localizedDescription)")
        }
    }

    private func handlePeerLeftBroadcast(_ message: JSONObject) {
        do {
            guard let payloadJSON = message["payload"] else {
                liveLog("peer_left ignored: missing payload envelope")
                return
            }
            let payload = try payloadJSON.decode(as: PeerLeftPayload.self)
            removeParticipantFromLiveHuddle(payload.membershipId, reason: "peer_left")
        } catch {
            print("❌ [Realtime Error] peer_left decode failed: \(error)")
        }
    }

    private func membershipId(fromPresenceKey presenceKey: String, entry: PresenceV2) -> UUID? {
        if let payload = try? entry.decodeState(as: LiveHuddlePresencePayload.self),
           let membershipUUID = payload.membershipUUID {
            return membershipUUID
        }
        if let uuid = UUID(uuidString: presenceKey) {
            return uuid
        }
        return UUID(uuidString: presenceKey.lowercased())
    }

    private func markParticipantDeparted(_ membershipId: UUID) {
        recentlyDepartedMembershipIds[membershipId] = Date()
    }

    private func clearDepartedParticipant(_ membershipId: UUID) {
        recentlyDepartedMembershipIds.removeValue(forKey: membershipId)
    }

    private func isRecentlyDeparted(_ membershipId: UUID) -> Bool {
        guard let departedAt = recentlyDepartedMembershipIds[membershipId] else { return false }
        if Date().timeIntervalSince(departedAt) > Self.departedSuppressionSeconds {
            recentlyDepartedMembershipIds.removeValue(forKey: membershipId)
            return false
        }
        return true
    }

    /// `presence_state` 全量快照在他人 untrack 后可能短暂仍含该成员；`presence_diff` 视为真实再次加入。
    private func shouldIgnoreStalePresenceJoin(_ membershipId: UUID, isSync: Bool) -> Bool {
        guard isRecentlyDeparted(membershipId) else { return false }
        return isSync
    }

    private func removeParticipantFromLiveHuddle(_ membershipId: UUID, reason: String) {
        guard membershipId != currentMembershipId else { return }
        markParticipantDeparted(membershipId)
        var next = participantSet
        let hadParticipant = next.remove(membershipId) != nil
        removeLivePeerState(for: membershipId)
        guard hadParticipant else { return }
        liveLog(
            "participant removed membership=\(membershipId.uuidString.prefix(8)) "
                + "reason=\(reason) remaining=\(next.count)"
        )
        applyActiveParticipants(next)
    }

    private func handlePeerSyncRequest(_ message: JSONObject) {
        do {
            guard let payloadJSON = message["payload"] else {
                liveLog("peer_sync_request ignored: missing payload envelope")
                return
            }
            let payload = try payloadJSON.decode(as: PeerSyncRequestPayload.self)
            liveLog(
                "peer_sync_request received from membership=\(payload.membershipId.uuidString.prefix(8)) "
                    + "liveActive=\(isLiveModeActive)"
            )
            guard payload.membershipId != currentMembershipId else { return }
            guard isLiveModeActive else {
                liveLog("peer_sync_request ignored: not in live mode")
                return
            }
            Task { await rebroadcastLocationToPeers() }
        } catch {
            print("❌ [Realtime Error] Failed to decode metadata: \(error)")
        }
    }

    private func applyPeerLocationFromPresence(_ entry: LiveHuddlePresencePayload) {
        guard let membershipUUID = entry.membershipUUID, membershipUUID != currentMembershipId else { return }
        guard isRecentlyDeparted(membershipUUID) == false else { return }
        guard let lat = entry.lat, let lng = entry.lng else {
            liveLog(
                "presence join without coords membership=\(entry.membershipId.prefix(8)) name=\(entry.name)"
            )
            return
        }

        let hadLocation = livePeerLocations[membershipUUID] != nil
        setLivePeerLocation(CLLocationCoordinate2D(latitude: lat, longitude: lng), for: membershipUUID)
        if let heading = entry.headingDegrees {
            livePeerHeadings[membershipUUID] = heading
        }
        if let level = entry.batteryLevel {
            livePeerBattery[membershipUUID] = LivePeerBatteryState(
                level: level,
                isCharging: entry.isCharging ?? false
            )
        }
        liveLog(
            "presence coords applied membership=\(entry.membershipId.prefix(8)) "
                + "lat=\(lat) lng=\(lng) updated=\(hadLocation)"
        )
    }

    private func handlePeerMoveBroadcast(_ message: JSONObject) {
        do {
            guard let payloadJSON = message["payload"] else {
                print("❌ [Realtime Error] peer_move missing payload envelope")
                return
            }
            let payload = try payloadJSON.decode(as: LiveLocationBroadcastPayload.self)
            guard payload.membershipId != currentMembershipId else { return }
            if isRecentlyDeparted(payload.membershipId) {
                liveLog(
                    "peer_move ignored departed membership=\(payload.membershipId.uuidString.prefix(8))"
                )
                return
            }
            let coordinate = CLLocationCoordinate2D(latitude: payload.lat, longitude: payload.lng)
            if participantSet.contains(payload.membershipId) == false {
                guard isLiveModeActive else {
                    liveLog(
                        "peer_move ignored stale membership=\(payload.membershipId.uuidString.prefix(8))"
                    )
                    return
                }
                liveLog(
                    "peer_move admitted before presence membership=\(payload.membershipId.uuidString.prefix(8))"
                )
                var admitted = participantSet
                admitted.insert(payload.membershipId)
                applyActiveParticipants(admitted)
            }

            let previousCount = livePeerLocations.count
            setLivePeerLocation(coordinate, for: payload.membershipId)
            if let heading = payload.headingDegrees {
                livePeerHeadings[payload.membershipId] = heading
            }
            livePeerBattery[payload.membershipId] = LivePeerBatteryState(
                level: payload.batteryLevel,
                isCharging: payload.isCharging
            )
            liveLog(
                "peer_move received membership=\(payload.membershipId.uuidString.prefix(8)) "
                    + "lat=\(payload.lat) lng=\(payload.lng) "
                    + "peerCount \(previousCount)→\(livePeerLocations.count)"
            )
        } catch {
            print("❌ [Realtime Error] Failed to decode metadata: \(error)")
        }
    }

    private func handlePresenceChange(_ presence: any PresenceAction) {
        let isSync = presence.rawMessage.event == "presence_state"
        let previousParticipants = participantSet
        // `presence_state` 是全量快照；`presence_diff` 在现有名册上增量更新。
        var nextParticipants = isSync ? Set<UUID>() : participantSet
        var newlyJoined = Set<UUID>()
        var joinedInThisDiff = Set<UUID>()

        liveLog(
            "presence \(isSync ? "sync" : "diff") joins=\(presence.joins.count) "
                + "leaves=\(presence.leaves.count) before=\(previousParticipants.count)"
        )

        for (_, presenceEntry) in presence.joins {
            do {
                let entry = try presenceEntry.decodeState(as: LiveHuddlePresencePayload.self)
                guard entry.status == "active", let membershipUUID = entry.membershipUUID else { continue }
                if shouldIgnoreStalePresenceJoin(membershipUUID, isSync: isSync) {
                    liveLog(
                        "presence join ignored departed(sync) membership=\(membershipUUID.uuidString.prefix(8))"
                    )
                    continue
                }
                clearDepartedParticipant(membershipUUID)
                joinedInThisDiff.insert(membershipUUID)
                if membershipUUID != currentMembershipId, previousParticipants.contains(membershipUUID) == false {
                    newlyJoined.insert(membershipUUID)
                }
                nextParticipants.insert(membershipUUID)
                applyPeerLocationFromPresence(entry)
            } catch {
                print("❌ [Realtime Error] Failed to decode metadata: \(error)")
            }
        }

        for (presenceKey, presenceEntry) in presence.leaves {
            guard let membershipUUID = membershipId(fromPresenceKey: presenceKey, entry: presenceEntry) else {
                liveLog("presence leave skipped: unknown key=\(presenceKey.prefix(12))")
                continue
            }

            if joinedInThisDiff.contains(membershipUUID) {
                liveLog("presence leave ignored (re-track) membership=\(membershipUUID.uuidString.prefix(8))")
                continue
            }

            if membershipUUID == currentMembershipId, isLiveModeActive {
                liveLog("presence self-leave while live — re-tracking")
                nextParticipants.insert(membershipUUID)
                let now = Date()
                if let last = lastSelfLeaveRetrackAt,
                   now.timeIntervalSince(last) < 3 {
                    continue
                }
                lastSelfLeaveRetrackAt = now
                Task { await ensurePresenceTracked() }
                continue
            }

            nextParticipants.remove(membershipUUID)
            if membershipUUID != currentMembershipId {
                markParticipantDeparted(membershipUUID)
                removeLivePeerState(for: membershipUUID)
                liveLog(
                    "presence peer cleared membership=\(membershipUUID.uuidString.prefix(8)) "
                        + "peerLocations=\(livePeerLocations.count)"
                )
            } else {
                liveLog("presence leave membership=\(membershipUUID.uuidString.prefix(8))")
            }
        }

        applyActiveParticipants(nextParticipants, newlyJoined: newlyJoined)
    }

    private func removeLivePeerState(for membershipId: UUID) {
        livePeerLocations.removeValue(forKey: membershipId)
        livePeerLocationUpdatedAt.removeValue(forKey: membershipId)
        livePeerHeadings.removeValue(forKey: membershipId)
        livePeerBattery.removeValue(forKey: membershipId)
    }

    private func setLivePeerLocation(
        _ coordinate: CLLocationCoordinate2D,
        for membershipId: UUID,
        updatedAt: Date = Date()
    ) {
        livePeerLocations[membershipId] = coordinate
        livePeerLocationUpdatedAt[membershipId] = updatedAt
    }

    private func pruneLivePeerState(to participants: Set<UUID>) {
        let staleIds = Set(livePeerLocations.keys).subtracting(participants)
        for membershipId in staleIds {
            removeLivePeerState(for: membershipId)
        }
    }

    private func recordLocalLiveLocation(_ location: CLLocation, heading: Double? = nil) {
        guard let currentMembershipId, isLiveModeActive else { return }
        setLivePeerLocation(location.coordinate, for: currentMembershipId)
        if let heading {
            livePeerHeadings[currentMembershipId] = heading
        }
        livePeerBattery[currentMembershipId] = LivePeerBatteryState(
            level: batteryMonitor.batteryLevel,
            isCharging: batteryMonitor.isCharging
        )
    }

    private func applyActiveParticipants(_ nextParticipants: Set<UUID>, newlyJoined: Set<UUID> = []) {
        var participants = nextParticipants
        if isLiveModeActive, let currentMembershipId {
            participants.insert(currentMembershipId)
        }

        let previousCount = activeParticipants.count
        participantSet = participants
        activeParticipants = participants.sorted {
            $0.uuidString.localizedStandardCompare($1.uuidString) == .orderedAscending
        }
        if activeParticipants.count != previousCount {
            liveLog(
                "activeParticipants \(previousCount)→\(activeParticipants.count) "
                    + "ids=\(activeParticipants.map { $0.uuidString.prefix(8) }.joined(separator: ",")) "
                    + "peerLocations=\(livePeerLocations.count)"
            )
        }

        pruneLivePeerState(to: participants)

        if participants.isEmpty, previousCount > 0 {
            Task {
                await disconnectChannel()
                liveLog("live channel closed: presence room empty")
            }
        }

        guard isLiveModeActive else { return }

        let peersMissingLocation = participants
            .filter {
                $0 != currentMembershipId
                    && livePeerLocations[$0] == nil
                    && isRecentlyDeparted($0) == false
            }

        if peersMissingLocation.isEmpty == false {
            liveLog(
                "peers missing live coords: "
                    + peersMissingLocation.map { $0.uuidString.prefix(8) }.joined(separator: ",")
            )
            Task {
                await seedPeerLocationsFromDatabase(for: peersMissingLocation)
                await requestPeerLocationSync()
            }
        }

        if newlyJoined.isEmpty == false {
            liveLog(
                "presence newly joined: "
                    + newlyJoined.map { $0.uuidString.prefix(8) }.joined(separator: ",")
            )
            Task { await rebroadcastLocationToPeers() }
        }
    }
    #endif

    private func rebroadcastLocationToPeers() async {
        guard isLiveModeActive else {
            liveLog("rebroadcast skipped: not in live mode")
            return
        }
        if let location = lastLiveBroadcastLocation ?? locationManager.location {
            liveLog("rebroadcast lat=\(location.coordinate.latitude) lng=\(location.coordinate.longitude)")
            await sendLiveBroadcast(location)
        } else {
            liveLog("rebroadcast skipped: no GPS fix yet")
        }
    }

    private func requestPeerLocationSync() async {
        #if canImport(Supabase)
        guard isLiveModeActive, let currentMembershipId else {
            liveLog("peer_sync_request skipped: live=\(isLiveModeActive)")
            return
        }
        guard await ensureLiveChannelReady(), let channel = liveChannel else {
            liveLog("peer_sync_request skipped: channel unavailable")
            return
        }
        let payload = PeerSyncRequestPayload(membershipId: currentMembershipId)
        do {
            try await channel.broadcast(event: "peer_sync_request", message: payload)
            liveLog("peer_sync_request sent membership=\(currentMembershipId.uuidString.prefix(8))")
        } catch {
            print("❌ [Realtime Error] peer_sync_request failed: \(error)")
        }
        #endif
    }

    /// 后进入 Live 时，用库中聚合位置作地图占位，直至收到秒级 `peer_move` / Presence 覆盖。
    private func seedPeerLocationsFromDatabase(for membershipIds: Set<UUID>) async {
        guard let householdId, membershipIds.isEmpty == false else { return }

        let targets = membershipIds.filter { membershipId in
            membershipId != currentMembershipId
                && livePeerLocations[membershipId] == nil
                && isRecentlyDeparted(membershipId) == false
        }
        guard targets.isEmpty == false else { return }

        let profileByMembership: [(UUID, UUID)] = targets.compactMap { membershipId in
            guard let profileId = profileIdForDatabase(membershipId: membershipId) else { return nil }
            return (membershipId, profileId)
        }
        guard profileByMembership.isEmpty == false else { return }

        liveLog("DB seed batch for \(profileByMembership.count) peer(s)")
        do {
            let records = try await locationStateService.fetchLocationStates(in: householdId)
            let recordByProfileId = Dictionary(
                uniqueKeysWithValues: records.map { ($0.profileId, $0) }
            )
            for (membershipId, profileId) in profileByMembership {
                guard livePeerLocations[membershipId] == nil else { continue }
                guard let record = recordByProfileId[profileId],
                      let payload = record.latestLocation else {
                    liveLog("DB seed empty row membership=\(membershipId.uuidString.prefix(8))")
                    continue
                }
                setLivePeerLocation(
                    payload.coordinate,
                    for: membershipId,
                    updatedAt: record.updatedAt
                )
                liveLog(
                    "DB seed ok membership=\(membershipId.uuidString.prefix(8)) "
                        + "lat=\(payload.latitude) lng=\(payload.longitude)"
                )
            }
        } catch {
            liveLog("DB seed batch failed: \(error.localizedDescription)")
        }
    }

    private func sendLiveBroadcast(_ location: CLLocation, heading: Double? = nil) async {
        #if canImport(Supabase)
        guard isLiveModeActive, let currentMembershipId else {
            liveLog("peer_move skipped: live=\(isLiveModeActive)")
            return
        }

        lastLiveBroadcastLocation = location
        recordLocalLiveLocation(location, heading: heading ?? currentHeadingDegrees)

        let now = Date()
        if let last = lastPeerMoveSentAt,
           now.timeIntervalSince(last) < Self.peerMoveMinInterval {
            return
        }

        guard await ensureLiveChannelReady(), let channel = liveChannel else {
            liveLog("peer_move skipped: channel unavailable")
            return
        }

        let payload = LiveLocationBroadcastPayload(
            membershipId: currentMembershipId,
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            headingDegrees: heading ?? currentHeadingDegrees,
            batteryLevel: batteryMonitor.batteryLevel,
            isCharging: batteryMonitor.isCharging
        )
        do {
            try await channel.broadcast(event: "peer_move", message: payload)
            lastPeerMoveSentAt = now
            liveLog(
                "peer_move sent membership=\(currentMembershipId.uuidString.prefix(8)) "
                    + "lat=\(payload.lat) lng=\(payload.lng) ws=\(channel.status == .subscribed)"
            )
        } catch {
            print("❌ [Realtime Error] peer_move failed: \(error)")
        }
        #endif
    }

    private func profileIdForDatabase(membershipId: UUID) -> UUID? {
        if membershipId == currentMembershipId {
            return currentProfileId
        }
        return profileIdByMembershipId[membershipId]
    }

    private func uploadToDatabaseIfNeeded(_ location: CLLocation, force: Bool = false) async {
        guard let householdId, let currentProfileId else { return }
        // Live 期间靠 Realtime 同步；避免与频道争用网络，仅在退出时 force 写库。
        guard force || isLiveModeActive == false else { return }

        let payload = LocationPayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let minDistanceMeters = LocationPersistPreferences.minUpdateDistanceMeters
        let minIntervalSeconds = LocationPersistPreferences.minUpdateIntervalSeconds

        do {
            let outcome = try await locationStateService.reportCurrentLocationIfNeeded(
                householdId: householdId,
                profileId: currentProfileId,
                coordinate: payload,
                minDistanceMeters: minDistanceMeters,
                minIntervalSeconds: minIntervalSeconds
            )
            switch outcome {
            case .persisted:
                liveLog("DB upload persisted lat=\(payload.latitude) lng=\(payload.longitude)")
            case .skippedGhost:
                liveLog("DB upload skipped: ghost mode")
            case .skippedWithinThreshold(let distanceMeters):
                liveLog(
                    "DB upload skipped: db locations[0] moved=\(Int(distanceMeters))m "
                        + "need≥\(Int(minDistanceMeters))m"
                )
            case .skippedWithinInterval(let elapsedSeconds):
                liveLog(
                    "DB upload skipped: elapsed=\(Int(elapsedSeconds))s "
                        + "need≥\(Int(minIntervalSeconds))s"
                )
            }
        } catch {
            liveLog("DB upload failed: \(error.localizedDescription)")
        }
    }

    private func resetInactivityTimer() {
        inactivitySecondsRemaining = Self.inactivityTimeoutSeconds
    }

    private func startInactivityWatchdog() {
        inactivityCancellable?.cancel()
        inactivityCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, isLiveModeActive else { return }
                if inactivitySecondsRemaining > 0 {
                    inactivitySecondsRemaining -= 1
                } else {
                    Task { await self.leaveLiveSession(silent: true) }
                }
            }
    }

    private func noteMovementIfSignificant(_ location: CLLocation) {
        guard isLiveModeActive else { return }
        if let anchor = lastMovementAnchor {
            let moved = location.distance(from: anchor)
            if moved >= Self.movementResetsInactivityMeters {
                lastMovementAnchor = location
                resetInactivityTimer()
            }
        } else {
            lastMovementAnchor = location
            resetInactivityTimer()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LiveLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard isLiveModeActive else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.startUpdatingLocation()
                manager.startUpdatingHeading()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let normalized = SimulatorLocationSupport.normalized(location)
        Task { @MainActor in
            LastKnownDeviceLocation.record(normalized)
            noteMovementIfSignificant(normalized)
            if isLiveModeActive {
                await sendLiveBroadcast(normalized)
            }
            await uploadToDatabaseIfNeeded(normalized)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let degrees: Double
        if newHeading.trueHeading >= 0 {
            degrees = newHeading.trueHeading
        } else if newHeading.magneticHeading >= 0 {
            degrees = newHeading.magneticHeading
        } else {
            return
        }

        Task { @MainActor in
            guard isLiveModeActive else { return }
            if let previous = currentHeadingDegrees,
               abs(previous - degrees) < 4 {
                currentHeadingDegrees = degrees
                return
            }
            currentHeadingDegrees = degrees
            if let location = lastLiveBroadcastLocation ?? manager.location {
                await sendLiveBroadcast(location, heading: degrees)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        Task { @MainActor in
            print("[LiveLocationManager] location error: \(error.localizedDescription)")
        }
        #endif
    }
}
