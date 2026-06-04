import MapKit
import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

struct LocationMainView: View {
    var isTabActive: Bool = true

    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator
    @StateObject private var viewModel: LocationMainViewModel
    @StateObject private var liveManager: LiveLocationManager
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isExitLiveModeAlertPresented = false

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

            if viewModel.isMemberListExpanded {
                mapDismissOverlay
            }

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    liveModeToggleControl
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                liveModeTopOverlay
                    .padding(.horizontal, 12)
                    .padding(.top, liveManager.showInactivityEndedNotice ? 8 : 0)

                Spacer()

                if liveManager.isLiveModeActive == false {
                    HStack(alignment: .bottom) {
                        ghostModeControl
                        Spacer()
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
        .sheet(isPresented: $viewModel.isGhostOptionsPresented) {
            LocationGhostOptionsSheet(isCurrentUserGhost: viewModel.isCurrentUserGhost) { option in
                Task { await viewModel.applyGhostOption(option) }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("退出实时位置模式", isPresented: $isExitLiveModeAlertPresented) {
            Button("退出实时模式", role: .destructive) {
                Task { await liveManager.leaveLiveSession() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后，群组将不再接收你的秒级位置更新。")
        }
        .task(id: locationRefreshToken) {
            guard isTabActive else { return }
            await bindLiveContext()
            await viewModel.refresh()
            liveManager.updateProfileIdByMembershipId(viewModel.profileIdByMembershipId)
            await viewModel.captureCurrentUserLocationForMap()
            await liveManager.observeHuddleLobby()
            fitCameraToLiveAndDisplayedMembers()
        }
        .onChange(of: isTabActive) { _, active in
            if active == false {
                viewModel.collapseMemberList()
            } else {
                Task {
                    await bindLiveContext()
                    await liveManager.observeHuddleLobby()
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
            fitCameraToLiveAndDisplayedMembers()
        }
        .onChange(of: liveManager.activeParticipants.count) { _, _ in
            fitCameraToLiveAndDisplayedMembers()
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
            }
            fitCameraToLiveAndDisplayedMembers()
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
            Text("Live Huddle 已因长时间无活动自动结束")
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
            Button("知道了") {
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
                liveManager.recordUserInteraction()
            }
            .accessibilityLabel("收起群组成员列表")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            ForEach(viewModel.mapDisplayedMembers) { member in
                if shouldRenderStandardMapContent(for: member) {
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
            MapUserLocationButton()
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
        liveManager.livePeerLocations
            .filter { liveManager.activeParticipants.contains($0.key) }
            .map { membershipId, coordinate in
                let member = viewModel.members.first(where: { $0.id == membershipId })
                let battery = liveManager.batteryDisplay(for: membershipId, rosterFallback: member)
                return LiveMapAnnotationItem(
                    id: membershipId,
                    displayName: member?.displayName ?? String(localized: "群组成员"),
                    coordinate: coordinate,
                    headingDegrees: liveManager.livePeerHeadings[membershipId],
                    batteryLevel: battery.level,
                    isCharging: battery.isCharging
                )
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    @MapContentBuilder
    private func memberMapContent(for member: UserLocationState) -> some MapContent {
        let coordinates = member.breadcrumbCoordinates
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

            if let history2 = member.historyLocation2?.coordinate {
                Annotation("", coordinate: history2, anchor: .center) {
                    Circle()
                        .fill(LocationMemberMapColors.historyDot(for: member.id, rank: 0))
                        .frame(width: 8, height: 8)
                }
            }

            if let history1 = member.historyLocation1?.coordinate {
                Annotation("", coordinate: history1, anchor: .center) {
                    Circle()
                        .fill(LocationMemberMapColors.historyDot(for: member.id, rank: 1))
                        .frame(width: 9, height: 9)
                }
            }

            if let current = member.currentLocation?.coordinate {
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
                Task {
                    await liveManager.startLiveSession()
                    fitCameraToLiveAndDisplayedMembers()
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
        .accessibilityLabel(liveManager.isLiveModeActive ? "退出实时位置模式" : "进入实时位置模式")
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

    // MARK: - Ghost control

    private var ghostModeControl: some View {
        Button {
            liveManager.recordUserInteraction()
            viewModel.presentGhostOptions()
        } label: {
            Image(systemName: viewModel.isCurrentUserGhost ? "location.slash.fill" : "location.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(viewModel.isCurrentUserGhost ? Color.secondary : Color.blue)
                .mapFloatingControlPlate()
        }
        .accessibilityLabel(viewModel.isCurrentUserGhost ? "位置已隐藏" : "位置共享设置")
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
        .accessibilityLabel(viewModel.isMemberListExpanded ? "收起群组成员列表" : "展开群组成员列表")
    }

    private var expandedMemberPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("群组位置")
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

            if liveManager.isLiveModeActive == false {
                ghostModeEntryRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else if viewModel.members.isEmpty, viewModel.isLoading == false {
                Text("暂无群组成员")
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
                    Text("当前群组")
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
        .accessibilityLabel("切换群组，\(GroupSwitcherData.currentName(for: appRouter))")
    }

    private var ghostModeEntryRow: some View {
        Button {
            liveManager.recordUserInteraction()
            viewModel.presentGhostOptions()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: viewModel.isCurrentUserGhost ? "location.slash.fill" : "location.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(viewModel.isCurrentUserGhost ? Color.secondary : Color.blue)
                Text(viewModel.isCurrentUserGhost ? "位置隐身中 · 点按管理" : "开启位置隐身")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemFill).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func bindLiveContext() async {
        viewModel.bind(
            householdId: appRouter.selectedHouseholdId,
            currentMembershipId: appRouter.selectedMembershipId,
            currentProfileId: appRouter.selectedProfileId
        )

        var authUserId: UUID?
        #if canImport(Supabase)
        authUserId = try? await SupabaseManager.shared.client.auth.session.user.id
        #endif

        liveManager.bind(
            householdId: appRouter.selectedHouseholdId,
            currentMembershipId: appRouter.selectedMembershipId,
            currentProfileId: appRouter.selectedProfileId,
            currentUserId: authUserId,
            displayName: viewModel.currentUser?.displayName
        )
    }

    private func shouldRenderStandardMapContent(for member: UserLocationState) -> Bool {
        if liveManager.isLiveModeActive,
           liveManager.livePeerLocations[member.id] != nil {
            return false
        }
        return true
    }

    private func polylineSegments(for coordinates: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        guard coordinates.count >= 2 else { return [] }
        return zip(coordinates, coordinates.dropFirst()).map { [$0, $1] }
    }

    private func fitCameraToLiveAndDisplayedMembers() {
        var coordinates = viewModel.mapDisplayedMembers.flatMap(\.breadcrumbCoordinates)
        if liveManager.isLiveModeActive {
            coordinates.append(contentsOf: liveManager.livePeerLocations.values)
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
