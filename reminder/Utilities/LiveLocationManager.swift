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
    static let databaseAggregationMeters: Double = 200
    private static let movementResetsInactivityMeters: Double = 8

    @Published private(set) var isLiveModeActive = false
    /// 当前 Huddle 内活跃成员的 **membership id**（来自 Presence，非数据库）。
    @Published private(set) var activeParticipants: [UUID] = []
    @Published private(set) var livePeerLocations: [UUID: CLLocationCoordinate2D] = [:]
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
    private var currentUserId: UUID?

    private var participantSet: Set<UUID> = []
    private var inactivitySecondsRemaining = inactivityTimeoutSeconds
    private var lastMovementAnchor: CLLocation?

    private var inactivityCancellable: AnyCancellable?
    private var batteryCancellable: AnyCancellable?
    private var receiveTask: Task<Void, Never>?

    #if canImport(Supabase)
    private var liveChannel: RealtimeChannelV2?
    private var presenceSubscription: RealtimeSubscription?
    #endif

    private var lastLoggedDBLocation: CLLocation?
    private var lastLiveBroadcastLocation: CLLocation?
    private var isChannelSubscribed = false

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

    var isHuddleActive: Bool {
        activeParticipants.isEmpty == false
    }

    var isCurrentUserInsideHuddle: Bool {
        guard let currentMembershipId else { return false }
        return isLiveModeActive || activeParticipants.contains(currentMembershipId)
    }

    func bind(householdId: UUID?, currentMembershipId: UUID?, currentUserId: UUID?) {
        let householdChanged = self.householdId != householdId
        self.householdId = householdId
        self.currentMembershipId = currentMembershipId
        self.currentUserId = currentUserId

        if householdChanged {
            Task {
                if isLiveModeActive {
                    await leaveLiveSession(silent: true)
                }
                await disconnectChannel()
                await observeHuddleLobby()
            }
        }
    }

    /// 被动订阅 Presence，用于 Lobby 卡片展示（不 track、不开启高精度 GPS）。
    func observeHuddleLobby() async {
        await ensureChannelConnected(shouldTrack: false)
    }

    /// 加入 Live Huddle：track Presence + 高精度 GPS + 广播位置。
    func startLiveSession() async {
        guard isLiveModeActive == false else { return }
        guard currentMembershipId != nil, currentUserId != nil else { return }

        isLiveModeActive = true
        livePeerLocations = [:]
        livePeerHeadings = [:]
        livePeerBattery = [:]
        currentHeadingDegrees = nil
        showInactivityEndedNotice = false
        batteryMonitor.refresh()
        lastLoggedDBLocation = nil
        lastMovementAnchor = nil
        resetInactivityTimer()

        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        await ensureChannelConnected(shouldTrack: true)
        #if DEBUG
        print("[LiveLocationManager] startLiveSession peers=\(livePeerLocations.count)")
        #endif
        startInactivityWatchdog()
    }

    /// 离开 Huddle：untrack Presence；最后一人离开时房间由 Realtime 自动清空。
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

        #if canImport(Supabase)
        if let channel = liveChannel {
            await channel.untrack()
        }
        #endif

        if let currentLocation = locationManager.location {
            await uploadToDatabaseIfNeeded(currentLocation, force: true)
        }

        isLiveModeActive = false
        livePeerLocations = [:]
        livePeerHeadings = [:]
        livePeerBattery = [:]

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

    private func ensureChannelConnected(shouldTrack: Bool) async {
        #if canImport(Supabase)
        guard let householdId else { return }

        let topic = "circle:\(householdId.uuidString.lowercased()):live_huddle"

        if liveChannel == nil {
            let channel = SupabaseManager.shared.client.realtimeV2.channel(topic) { config in
                config.isPrivate = true
            }
            liveChannel = channel

            presenceSubscription?.cancel()
            presenceSubscription = channel.onPresenceChange { [weak self] presence in
                Task { @MainActor in
                    self?.handlePresenceChange(presence)
                }
            }

            do {
                try await channel.subscribeWithError()
                isChannelSubscribed = true
                #if DEBUG
                print("[LiveLocationManager] subscribed topic=\(topic)")
                #endif
                startPeerMoveBroadcastReceiver(on: channel)
            } catch {
                isChannelSubscribed = false
                #if DEBUG
                print("[LiveLocationManager] subscribe failed topic=\(topic): \(error.localizedDescription)")
                #endif
            }
        }

        if shouldTrack, isChannelSubscribed, let currentUserId, let currentMembershipId {
            let payload = LiveHuddlePresencePayload(
                userId: currentUserId,
                membershipId: currentMembershipId
            )
            do {
                try await liveChannel?.track(payload)
                #if DEBUG
                print("[LiveLocationManager] track membership=\(currentMembershipId.uuidString.prefix(8))")
                #endif
            } catch {
                #if DEBUG
                print("[LiveLocationManager] track failed: \(error.localizedDescription)")
                #endif
            }
        }
        #endif
    }

    private func disconnectChannel() async {
        inactivityCancellable?.cancel()
        inactivityCancellable = nil
        receiveTask?.cancel()
        receiveTask = nil

        #if canImport(Supabase)
        presenceSubscription?.cancel()
        presenceSubscription = nil

        if let channel = liveChannel {
            await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
        }
        liveChannel = nil
        #endif

        isChannelSubscribed = false
        participantSet = []
        activeParticipants = []
        livePeerLocations = [:]
        livePeerHeadings = [:]
        livePeerBattery = [:]
        currentHeadingDegrees = nil
        lastLiveBroadcastLocation = nil
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

    private func handlePeerMoveBroadcast(_ message: JSONObject) {
        do {
            guard let payloadJSON = message["payload"] else {
                #if DEBUG
                print("[LiveLocationManager] peer_move missing payload envelope")
                #endif
                return
            }
            let payload = try payloadJSON.decode(as: LiveLocationBroadcastPayload.self)
            guard payload.membershipId != currentMembershipId else { return }

            let coordinate = CLLocationCoordinate2D(latitude: payload.lat, longitude: payload.lng)
            let previousCount = livePeerLocations.count
            livePeerLocations[payload.membershipId] = coordinate
            if let heading = payload.headingDegrees {
                livePeerHeadings[payload.membershipId] = heading
            }
            livePeerBattery[payload.membershipId] = LivePeerBatteryState(
                level: payload.batteryLevel,
                isCharging: payload.isCharging
            )
            #if DEBUG
            if livePeerLocations.count != previousCount {
                print(
                    "[LiveLocationManager] livePeerLocations count=\(livePeerLocations.count) "
                        + "latest=\(payload.membershipId.uuidString.prefix(8))"
                )
            }
            #endif
        } catch {
            #if DEBUG
            print("[LiveLocationManager] peer_move decode failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func handlePresenceChange(_ presence: any PresenceAction) {
        let previousCount = activeParticipants.count

        if let joins = try? presence.decodeJoins(as: LiveHuddlePresencePayload.self) {
            for entry in joins where entry.status == "active" {
                participantSet.insert(entry.membershipId)
            }
        } else {
            #if DEBUG
            print("[LiveLocationManager] presence joins decode failed")
            #endif
        }

        if let leaves = try? presence.decodeLeaves(as: LiveHuddlePresencePayload.self) {
            for entry in leaves {
                participantSet.remove(entry.membershipId)
                livePeerLocations.removeValue(forKey: entry.membershipId)
                livePeerHeadings.removeValue(forKey: entry.membershipId)
                livePeerBattery.removeValue(forKey: entry.membershipId)
            }
        } else {
            #if DEBUG
            print("[LiveLocationManager] presence leaves decode failed")
            #endif
        }

        activeParticipants = participantSet.sorted {
            $0.uuidString.localizedStandardCompare($1.uuidString) == .orderedAscending
        }

        #if DEBUG
        if activeParticipants.count != previousCount {
            print("[LiveLocationManager] activeParticipants count=\(activeParticipants.count)")
        }
        #endif
    }
    #endif

    private func sendLiveBroadcast(_ location: CLLocation, heading: Double? = nil) async {
        #if canImport(Supabase)
        guard isLiveModeActive, let channel = liveChannel, let currentMembershipId else { return }
        lastLiveBroadcastLocation = location
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
        } catch {
            #if DEBUG
            print("[LiveLocationManager] broadcast failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    private func uploadToDatabaseIfNeeded(_ location: CLLocation, force: Bool = false) async {
        guard let householdId, let currentMembershipId else { return }

        if force == false, let lastLoggedDBLocation {
            let distance = location.distance(from: lastLoggedDBLocation)
            if distance < Self.databaseAggregationMeters {
                return
            }
        }

        let payload = LocationPayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        do {
            _ = try await locationStateService.reportCurrentLocationIfNeeded(
                householdId: householdId,
                membershipId: currentMembershipId,
                coordinate: payload,
                minDistanceMeters: Self.databaseAggregationMeters
            )
            lastLoggedDBLocation = location
        } catch {
            #if DEBUG
            print("[LiveLocationManager] DB upload skipped: \(error.localizedDescription)")
            #endif
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
        Task { @MainActor in
            noteMovementIfSignificant(location)
            if isLiveModeActive {
                await sendLiveBroadcast(location)
            }
            await uploadToDatabaseIfNeeded(location)
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
