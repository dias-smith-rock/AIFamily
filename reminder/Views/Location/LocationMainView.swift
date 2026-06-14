import MapKit
import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

struct LocationMainView: View {
    var isTabActive: Bool = true

    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator
    @StateObject private var viewModel: LocationMainViewModel
    @StateObject private var liveManager: LiveLocationManager
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isExitLiveModeAlertPresented = false
    @State private var isRefreshingMapLocations = false
    @State private var isLiveSharingPanelExpanded = false
    @State private var fitCameraTask: Task<Void, Never>?
    @AppStorage(LocationMapDisplayPreferences.displayCountStorageKey)
    private var mapHistoryDisplayCount = LocationMapDisplayPreferences.defaultHistoryDisplayCount

    private var effectiveMapHistoryDisplayCount: Int {
        PremiumLimits.clampedMapHistoryDisplayCount(
            mapHistoryDisplayCount,
            hasPremium: appRouter.hasPremiumAccess
        )
    }

    init(
        isTabActive: Bool = true,
        viewModel: LocationMainViewModel? = nil,
        liveManager: LiveLocationManager? = nil
    ) {
        self.isTabActive = isTabActive
        _viewModel = StateObject(
            wrappedValue: viewModel ?? AppViewModels.makeLocationMainViewModel()
        )
        _liveManager = StateObject(
            wrappedValue: liveManager ?? AppViewModels.makeLiveLocationManager()
        )
    }

    var body: some View {
        ZStack {
            mapLayer

            if viewModel.isMemberListExpanded || isLiveSharingPanelExpanded {
                mapDismissOverlay
            }

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    liveModeToggleControl
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        if liveManager.isLiveModeActive == false {
                            mapRefreshControl
                        }
                        mapRecenterControl
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                liveModeTopOverlay
                    .padding(.horizontal, 12)
                    .padding(.top, liveManager.showInactivityEndedNotice ? 8 : 0)

                Spacer()

                if liveManager.isLiveModeActive {
                    HStack(alignment: .bottom) {
                        Spacer(minLength: 0)
                        liveSharingOverlay
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    HStack(alignment: .bottom) {
                        Spacer(minLength: 0)
                        memberListOverlay
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: liveManager.isLiveModeActive)
        .animation(.easeInOut(duration: 0.3), value: liveManager.showInactivityEndedNotice)
        .animation(.easeInOut(duration: 0.3), value: liveManager.activeParticipants.count)
        .alert(L10n.Location.exitLiveLocationMode, isPresented: $isExitLiveModeAlertPresented) {
            Button(L10n.Common.exitLiveMode, role: .destructive) {
                Task { await liveManager.leaveLiveSession() }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Family.afterYouLeaveTheGroupWillNoLongerReceive.localized)
        }
        .task(id: locationRefreshToken) {
            guard isTabActive else { return }
            _ = await LocationAuthorizationRequester.shared.requestWhenInUseIfNeeded()
            bindLiveContext()
            await viewModel.refresh()
            liveManager.updateProfileIdByMembershipId(viewModel.profileIdByMembershipId)
            viewModel.applyCachedDeviceLocationForMap()
            fitCameraToLiveAndDisplayedMembers()
            Task {
                if await NetworkMonitor.shared.isConnected {
                    await liveManager.observeHuddleLobby()
                }
                await viewModel.captureCurrentUserLocationForMap()
                fitCameraToLiveAndDisplayedMembers()
            }
        }
        .onChange(of: isTabActive) { _, active in
            if active == false {
                viewModel.collapseMemberList()
                isLiveSharingPanelExpanded = false
            } else {
                bindLiveContext()
                viewModel.applyCachedDeviceLocationForMap()
                fitCameraToLiveAndDisplayedMembers()
                Task {
                    _ = await LocationAuthorizationRequester.shared.requestWhenInUseIfNeeded()
                    if await NetworkMonitor.shared.isConnected {
                        await liveManager.observeHuddleLobby()
                    }
                    await viewModel.captureCurrentUserLocationForMap()
                    fitCameraToLiveAndDisplayedMembers()
                }
            }
        }
        .onChange(of: viewModel.mapDisplayedMembers.map(\.id)) { _, _ in
            fitCameraToLiveAndDisplayedMembers()
        }
        .onChange(of: viewModel.currentUserLiveLocation) { _, _ in
            fitCameraToLiveAndDisplayedMembers()
        }
        .onChange(of: liveManager.livePeerLocations.count) { _, _ in
            scheduleFitCameraToLiveAndDisplayedMembers()
        }
        .onChange(of: liveManager.activeParticipants.count) { _, _ in
            scheduleFitCameraToLiveAndDisplayedMembers()
        }
        .onChange(of: viewModel.profileIdByMembershipId) { _, map in
            liveManager.updateProfileIdByMembershipId(map)
        }
        .onChange(of: DeviceBatteryMonitor.shared.batteryLevel) { _, _ in
            viewModel.syncCurrentUserBatteryFromDevice()
        }
        .onChange(of: DeviceBatteryMonitor.shared.isCharging) { _, _ in
            viewModel.syncCurrentUserBatteryFromDevice()
        }
        .onChange(of: liveManager.isLiveModeActive) { _, isActive in
            viewModel.setLiveModeActive(isActive)
            BackgroundLocationCoordinator.shared.setPausedForLiveMode(isActive)
            if isActive {
                viewModel.collapseMemberList()
                isLiveSharingPanelExpanded = false
                viewModel.applyCachedDeviceLocationForMap()
                scheduleFitCameraToLiveAndDisplayedMembers()
                Task { await viewModel.captureCurrentUserLocationForMap(timeoutSeconds: 2) }
            }
            scheduleFitCameraToLiveAndDisplayedMembers()
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                liveManager.recordUserInteraction()
            }
        )
    }

    @ViewBuilder
    private var liveModeTopOverlay: some View {
        if liveManager.showInactivityEndedNotice {
            inactivityEndedBanner
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var inactivityEndedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.secondary)
            Text(L10n.Common.liveLocationSharingEndedAutomaticallyDueTo.localized)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
            Button(L10n.Common.gotIt) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    liveManager.dismissInactivityNotice()
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.easeInOut(duration: 0.25)) {
                    liveManager.dismissInactivityNotice()
                }
            }
        }
    }

    private var huddleParticipantMembers: [UserLocationState] {
        viewModel.members.filter { liveManager.activeParticipants.contains($0.id) }
    }

    private var lobbyParticipantMembers: [UserLocationState] {
        huddleParticipantMembers
    }

    private var shouldShowLobbyPortal: Bool {
        liveManager.isHuddleActive
            && liveManager.isLiveModeActive == false
            && lobbyParticipantMembers.isEmpty == false
    }

    private var locationRefreshToken: String {
        let household = appRouter.selectedHouseholdId?.uuidString ?? "none"
        let membership = appRouter.selectedMembershipId?.uuidString ?? "none"
        return "\(isTabActive)-\(household)-\(membership)"
    }

    private var mapDismissOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture {
                viewModel.collapseMemberList()
                isLiveSharingPanelExpanded = false
                liveManager.recordUserInteraction()
            }
            .accessibilityLabel(L10n.Family.collapseGroupMemberList)
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            if liveManager.isLiveModeActive == false {
                ForEach(viewModel.mapDisplayedMembers) { member in
                    memberMapContent(for: member)
                }
            }

            if liveManager.isLiveModeActive {
                ForEach(liveHuddleMapAnnotations) { item in
                    let battery = liveManager.batteryDisplay(
                        for: item.id,
                        rosterFallback: viewModel.members.first(where: { $0.id == item.id })
                    )
                    Annotation(
                        item.displayName,
                        coordinate: item.coordinate,
                        anchor: LivePeerMapMarker.mapCoordinateAnchor
                    ) {
                        LivePeerMapMarker(
                            displayName: item.displayName,
                            batteryLevel: battery.level,
                            isCharging: battery.isCharging,
                            lastUpdatedAt: liveManager.locationUpdatedAt(
                                for: item.id,
                                rosterFallback: viewModel.members.first(where: { $0.id == item.id })
                            ),
                            headingDegrees: item.headingDegrees
                        )
                        .animation(.easeInOut(duration: 0.5), value: item.coordinate.latitude)
                        .animation(.easeInOut(duration: 0.5), value: item.coordinate.longitude)
                        .animation(.linear(duration: 0.12), value: item.headingDegrees)
                    }
                }
            }
        }
        .mapControls {
            MapCompass()
        }
        .ignoresSafeArea(edges: .top)
    }

    private struct LiveMapAnnotationItem: Identifiable {
        let id: UUID
        let displayName: String
        let coordinate: CLLocationCoordinate2D
        let headingDegrees: Double?
        let batteryLevel: Int
        let isCharging: Bool
    }

    private var liveHuddleMapAnnotations: [LiveMapAnnotationItem] {
        liveManager.activeParticipants.compactMap { membershipId in
            guard let coordinate = liveAnnotationCoordinate(for: membershipId) else { return nil }
            let member = viewModel.members.first(where: { $0.id == membershipId })
            let battery = liveManager.batteryDisplay(for: membershipId, rosterFallback: member)
            let heading = membershipId == appRouter.selectedMembershipId
                ? liveManager.currentHeadingDegrees ?? liveManager.livePeerHeadings[membershipId]
                : liveManager.livePeerHeadings[membershipId]
            return LiveMapAnnotationItem(
                id: membershipId,
                displayName: member?.displayName ?? L10n.Family.groupMembers.string(),
                coordinate: coordinate,
                headingDegrees: heading,
                batteryLevel: battery.level,
                isCharging: battery.isCharging
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func liveAnnotationCoordinate(for membershipId: UUID) -> CLLocationCoordinate2D? {
        if let coordinate = liveManager.livePeerLocations[membershipId] {
            return coordinate
        }
        guard membershipId == appRouter.selectedMembershipId else { return nil }
        if let payload = viewModel.currentUserLiveLocation {
            return payload.coordinate
        }
        return LastKnownDeviceLocation.cachedCoordinate()
    }

    @MapContentBuilder
    private func memberMapContent(for member: UserLocationState) -> some MapContent {
        let displayCount = effectiveMapHistoryDisplayCount
        let visibleLocations = member.mapVisibleLocations(displayCount: displayCount)
        let coordinates = member.mapVisibleBreadcrumbCoordinates(displayCount: displayCount)
        let accent = LocationMemberMapColors.accent(for: member.id)
        let segmentCount = max(0, coordinates.count - 1)

        Group {
            if coordinates.count >= 2 {
                ForEach(Array(polylineSegments(for: coordinates).enumerated()), id: \.offset) { index, segment in
                    MapPolyline(coordinates: segment)
                        .stroke(
                            LocationMemberMapColors.trajectorySegment(
                                for: member.id,
                                segmentIndex: index,
                                totalSegments: segmentCount
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }
            }

            let history = Array(visibleLocations.dropFirst())
            ForEach(Array(history.enumerated()), id: \.offset) { index, historyPoint in
                let rank = history.count - 1 - index
                let showsInfoBadge = historyPoint.batteryLevel != nil || historyPoint.recordedAt != nil
                let dotDiameter = history.count > 1
                    ? 8.0 + (Double(rank) / Double(history.count - 1)) * 2.0
                    : 9.0
                Annotation(
                    "",
                    coordinate: historyPoint.coordinate,
                    anchor: MapHistoryTrajectoryMarker.mapCoordinateAnchor(
                        dotDiameter: dotDiameter,
                        showsInfoBadge: showsInfoBadge
                    )
                ) {
                    MapHistoryTrajectoryMarker(
                        dotDiameter: dotDiameter,
                        dotColor: LocationMemberMapColors.historyDot(
                            for: member.id,
                            rank: rank,
                            totalHistoryCount: history.count
                        ),
                        batteryLevel: historyPoint.clampedBatteryLevel,
                        isCharging: historyPoint.isCharging ?? false,
                        recordedAt: historyPoint.recordedAt
                    )
                }
            }

            if let current = visibleLocations.first?.coordinate {
                Annotation(
                    member.displayName,
                    coordinate: current,
                    anchor: liveManager.isLiveModeActive && member.isCurrentUser
                        ? LivePeerMapMarker.mapCoordinateAnchor
                        : .center
                ) {
                    if liveManager.isLiveModeActive, member.isCurrentUser {
                        let battery = liveManager.batteryDisplay(for: member.id, rosterFallback: member)
                        LivePeerMapMarker(
                            displayName: member.displayName,
                            batteryLevel: battery.level,
                            isCharging: battery.isCharging,
                            lastUpdatedAt: liveManager.locationUpdatedAt(for: member.id, rosterFallback: member),
                            headingDegrees: liveManager.currentHeadingDegrees
                        )
                        .animation(.easeInOut(duration: 0.45), value: current.latitude)
                        .animation(.easeInOut(duration: 0.45), value: current.longitude)
                        .animation(.linear(duration: 0.12), value: liveManager.currentHeadingDegrees)
                    } else {
                        UserMapAvatarView(
                            displayName: member.displayName,
                            batteryLevel: member.clampedBatteryLevel,
                            isCharging: member.isCharging,
                            lastUpdatedAt: member.currentLocationUpdatedAt,
                            mapAccentColor: accent
                        )
                        .animation(.easeInOut(duration: 0.45), value: current.latitude)
                        .animation(.easeInOut(duration: 0.45), value: current.longitude)
                    }
                }
            }
        }
    }

    // MARK: - Live mode toggle (top-leading)

    private var liveModeToggleControl: some View {
        Button {
            liveManager.recordUserInteraction()
            if liveManager.isLiveModeActive {
                isExitLiveModeAlertPresented = true
            } else {
                viewModel.applyCachedDeviceLocationForMap()
                scheduleFitCameraToLiveAndDisplayedMembers()
                Task {
                    await liveManager.startLiveSession()
                    scheduleFitCameraToLiveAndDisplayedMembers()
                }
            }
        } label: {
            Image(systemName: liveModeToggleSymbolName)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(liveModeToggleForegroundColor)
                .mapFloatingControlPlate()
                .overlay {
                    if liveManager.isLiveModeActive {
                        Circle()
                            .stroke(Color.green, lineWidth: 2)
                    }
                }
        }
        .accessibilityLabel(
            liveManager.isLiveModeActive
                ? L10n.Location.exitLiveLocationMode.string(locale: locale)
                : L10n.Location.enterLiveLocationMode.string(locale: locale)
        )
        .animation(.easeInOut(duration: 0.25), value: liveManager.isLiveModeActive)
    }

    private var liveModeToggleSymbolName: String {
        liveManager.isLiveModeActive
            ? "location.slash.circle.fill"
            : "antenna.radiowaves.left.and.right"
    }

    private var liveModeToggleForegroundColor: Color {
        liveManager.isLiveModeActive ? .orange : .green
    }

    /// 替代系统 `MapUserLocationButton`，与左上角 Live 按钮同一行、同一安全区内边距。
    private var mapRefreshControl: some View {
        Button {
            liveManager.recordUserInteraction()
            Task { await refreshMapLocations() }
        } label: {
            Group {
                if isRefreshingMapLocations {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.blue)
                }
            }
            .mapFloatingControlPlate()
        }
        .disabled(isRefreshingMapLocations)
        .accessibilityLabel(L10n.Location.refreshLocations)
    }

    private var mapRecenterControl: some View {
        Button {
            liveManager.recordUserInteraction()
            centerCameraOnCurrentUser()
        } label: {
            Image(systemName: "location.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.blue)
                .mapFloatingControlPlate()
        }
        .accessibilityLabel(L10n.Location.locateMyLocation)
    }

    // MARK: - Live sharing panel

    private var liveSharingMembers: [UserLocationState] {
        liveManager.activeParticipants.compactMap { membershipId in
            viewModel.members.first(where: { $0.id == membershipId })
        }
    }

    private var liveSharingOverlay: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if isLiveSharingPanelExpanded {
                expandedLiveSharingPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            liveSharingToggleButton
        }
        .animation(.easeInOut(duration: 0.25), value: isLiveSharingPanelExpanded)
        .animation(.easeInOut(duration: 0.3), value: liveManager.activeParticipants.count)
    }

    private var liveSharingToggleButton: some View {
        Button {
            liveManager.recordUserInteraction()
            isLiveSharingPanelExpanded.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(Color.blue)
                    .mapFloatingControlPlate(diameter: MapFloatingControlStyle.largeDiameter)

                if liveManager.activeParticipants.isEmpty == false {
                    Text("\(liveManager.activeParticipants.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .accessibilityLabel(isLiveSharingPanelExpanded ? L10n.Location.collapseLocationSharing : L10n.Location.expandLocationSharing)
    }

    private var expandedLiveSharingPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.Settings.locationSharingSection.localized)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if liveSharingMembers.isEmpty {
                Text(L10n.Family.noMembersSharingLocation.localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 48), spacing: 12)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(liveSharingMembers) { member in
                            Button {
                                focusMapOnLiveSharingMember(member)
                            } label: {
                                LocationMemberAvatarView(
                                    displayName: member.displayName,
                                    avatarURL: member.avatarURL,
                                    size: 44
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(member.displayName)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func focusMapOnLiveSharingMember(_ member: UserLocationState) {
        liveManager.recordUserInteraction()
        isLiveSharingPanelExpanded = false
        guard let coordinate = liveAnnotationCoordinate(for: member.id) else { return }
        cameraPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1_200,
                longitudinalMeters: 1_200
            )
        )
    }

    // MARK: - Member list

    private var memberListOverlay: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if viewModel.isMemberListExpanded {
                expandedMemberPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            memberListToggleButton
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isMemberListExpanded)
        .animation(.easeInOut(duration: 0.3), value: shouldShowLobbyPortal)
    }

    private var memberListToggleButton: some View {
        Button {
            liveManager.recordUserInteraction()
            viewModel.toggleMemberList()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(Color.blue)
                    .mapFloatingControlPlate(diameter: MapFloatingControlStyle.largeDiameter)

                if viewModel.selectedMemberIDs.isEmpty == false {
                    Text("\(viewModel.selectedMemberIDs.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .accessibilityLabel(viewModel.isMemberListExpanded ? L10n.Family.collapseGroupMemberList : L10n.Family.expandGroupMemberList)
    }

    private var expandedMemberPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.Family.groupLocations.localized)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            organizationSwitcherRow
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if shouldShowLobbyPortal {
                LiveHuddleLobbyCard(participants: lobbyParticipantMembers) {
                    Task {
                        await liveManager.startLiveSession()
                        fitCameraToLiveAndDisplayedMembers()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            locationGhostToggleRow
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else if viewModel.members.isEmpty, viewModel.isLoading == false {
                Text(L10n.Family.noGroupMembersYet.localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.members) { member in
                        LocationMemberSheetRow(
                            member: member,
                            isSelected: viewModel.isSelected(memberID: member.id),
                            isInLiveHuddle: liveManager.isLiveModeActive
                                && liveManager.activeParticipants.contains(member.id),
                            onSelectionChange: { selected in
                                guard viewModel.isCurrentUserSelectionLocked(memberID: member.id) == false else {
                                    return
                                }
                                liveManager.recordUserInteraction()
                                viewModel.setSelected(selected, for: member.id)
                            }
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                        if member.id != viewModel.members.last?.id {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }


    private var locationGhostToggleRow: some View {
        Toggle(isOn: locationGhostModeBinding) {
            Text(L10n.Settings.locationGhostToggle.localized)
                .font(.subheadline)
        }
        .disabled(liveManager.isLiveModeActive)
        .accessibilityLabel(L10n.Settings.locationGhostToggle)
    }

    private var locationGhostModeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isLocationGhostModeEnabled },
            set: { newValue in
                if newValue, PremiumLimits.canEnableLocationGhostMode(hasPremium: appRouter.hasPremiumAccess) == false {
                    appRouter.presentPremiumUpgrade()
                    return
                }
                Task { await viewModel.setLocationGhostMode(newValue) }
            }
        )
    }

    private var organizationSwitcherRow: some View {
        Button {
            liveManager.recordUserInteraction()
            groupSwitcher.showSwitchGroupDialog = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Family.currentGroup.localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(GroupSwitcherData.currentName(for: appRouter))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemFill).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Family.switchGroups.formatted(locale: locale, GroupSwitcherData.currentName(for: appRouter)))
    }

    // MARK: - Helpers

    /// 从服务端拉取成员 `location_states`，并更新本机 GPS 展示。
    private func refreshMapLocations() async {
        guard isRefreshingMapLocations == false else { return }
        isRefreshingMapLocations = true
        defer { isRefreshingMapLocations = false }

        bindLiveContext()
        await viewModel.refresh()
        liveManager.updateProfileIdByMembershipId(viewModel.profileIdByMembershipId)
        viewModel.applyCachedDeviceLocationForMap()

        await viewModel.captureCurrentUserLocationForMap()
        if await NetworkMonitor.shared.isConnected {
            await liveManager.observeHuddleLobby()
        }
    }

    private func bindLiveContext() {
        viewModel.bind(
            householdId: appRouter.selectedHouseholdId,
            currentMembershipId: appRouter.selectedMembershipId,
            currentProfileId: appRouter.selectedProfileId
        )

        var authUserId: UUID?
        #if canImport(Supabase)
        authUserId = SupabaseManager.shared.client.auth.currentSession?.user.id
        #endif

        liveManager.bind(
            householdId: appRouter.selectedHouseholdId,
            currentMembershipId: appRouter.selectedMembershipId,
            currentProfileId: appRouter.selectedProfileId,
            currentUserId: authUserId,
            displayName: viewModel.currentUser?.displayName
        )
    }

    private func polylineSegments(for coordinates: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        guard coordinates.count >= 2 else { return [] }
        return zip(coordinates, coordinates.dropFirst()).map { [$0, $1] }
    }

    private func centerCameraOnCurrentUser() {
        let coordinate: CLLocationCoordinate2D?
        if let live = viewModel.currentUserLiveLocation {
            coordinate = CLLocationCoordinate2D(latitude: live.latitude, longitude: live.longitude)
        } else if let current = viewModel.currentUser?.currentLocation?.coordinate {
            coordinate = current
        } else {
            coordinate = nil
        }
        guard let coordinate else { return }
        cameraPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1_200,
                longitudinalMeters: 1_200
            )
        )
    }

    private func scheduleFitCameraToLiveAndDisplayedMembers() {
        fitCameraTask?.cancel()
        fitCameraTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard Task.isCancelled == false else { return }
            fitCameraToLiveAndDisplayedMembers()
        }
    }

    private func fitCameraToLiveAndDisplayedMembers() {
        let coordinates: [CLLocationCoordinate2D]
        if liveManager.isLiveModeActive {
            coordinates = liveHuddleMapAnnotations.map(\.coordinate)
        } else {
            let displayCount = effectiveMapHistoryDisplayCount
            coordinates = viewModel.mapDisplayedMembers.flatMap {
                $0.mapVisibleBreadcrumbCoordinates(displayCount: displayCount)
            }
        }
        guard let first = coordinates.first else {
            cameraPosition = .automatic
            return
        }
        guard coordinates.count > 1 else {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: first,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200
                )
            )
            return
        }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            rect = rect.union(pointRect)
        }
        rect = rect.insetBy(dx: -rect.size.width * 0.25, dy: -rect.size.height * 0.25)
        cameraPosition = .rect(rect)
    }

}

#Preview {
    LocationMainView(
        viewModel: LocationMainViewModel(
            locationStateService: MockLocationStateDataService(seedPreview: true),
            membershipService: MockHouseholdMembershipDataService(),
            previewMembers: UserLocationState.previewHousehold
        )
    )
    .environmentObject(AppRouter())
    .environmentObject(GroupSwitcherCoordinator())
}
