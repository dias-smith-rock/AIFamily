import MapKit
import SwiftUI

struct LocationMainView: View {
    var isTabActive: Bool = true

    @StateObject private var viewModel = LocationMainViewModel()
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            mapLayer

            if viewModel.isMemberListExpanded {
                mapDismissOverlay
            }

            VStack {
                HStack {
                    Spacer()
                    ghostModeControl
                }
                .padding(.top, 12)
                .padding(.trailing, 16)

                Spacer()

                HStack {
                    Spacer()
                    memberListOverlay
                }
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
        .confirmationDialog(
            "位置共享",
            isPresented: $viewModel.isGhostOptionsPresented,
            titleVisibility: .visible
        ) {
            Button("暂停 1 小时") {
                viewModel.applyGhostOption(.pauseOneHour)
            }
            Button("直到今晚") {
                viewModel.applyGhostOption(.untilTonight)
            }
            Button("保持隐藏") {
                viewModel.applyGhostOption(.keepHidden)
            }
            Button("停止隐藏") {
                viewModel.applyGhostOption(.stopHiding)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择隐藏位置的时长")
        }
        .onAppear {
            fitCameraToDisplayedMembers()
        }
        .onChange(of: isTabActive) { _, active in
            if active == false {
                viewModel.collapseMemberList()
            }
        }
        .onChange(of: viewModel.mapDisplayedMembers.map(\.id)) { _, _ in
            fitCameraToDisplayedMembers()
        }
    }

    /// 列表展开时点击地图区域收起浮层（不阻挡右下角按钮与面板）。
    private var mapDismissOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture {
                viewModel.collapseMemberList()
            }
            .accessibilityLabel("收起家人列表")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            ForEach(viewModel.mapDisplayedMembers) { member in
                memberMapContent(for: member)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .ignoresSafeArea(edges: .top)
    }

    @MapContentBuilder
    private func memberMapContent(for member: UserLocationState) -> some MapContent {
        let coordinates = member.breadcrumbCoordinates

        Group {
            if coordinates.count >= 2 {
                ForEach(Array(polylineSegments(for: coordinates).enumerated()), id: \.offset) { index, segment in
                    MapPolyline(coordinates: segment)
                        .stroke(
                            segmentStrokeColor(segmentIndex: index, totalSegments: coordinates.count - 1),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [7, 5])
                        )
                }
            }

            if let history2 = member.historyLocation2?.coordinate {
                Annotation("", coordinate: history2, anchor: .center) {
                    Circle()
                        .fill(Color.blue.opacity(0.28))
                        .frame(width: 8, height: 8)
                }
            }

            if let history1 = member.historyLocation1?.coordinate {
                Annotation("", coordinate: history1, anchor: .center) {
                    Circle()
                        .fill(Color.blue.opacity(0.45))
                        .frame(width: 9, height: 9)
                }
            }

            if let current = member.currentLocation?.coordinate {
                Annotation(member.displayName, coordinate: current) {
                    UserMapAvatarView(
                        displayName: member.displayName,
                        batteryLevel: member.clampedBatteryLevel,
                        isCharging: member.isCharging
                    )
                    .animation(.easeInOut(duration: 0.45), value: current.latitude)
                    .animation(.easeInOut(duration: 0.45), value: current.longitude)
                }
            }
        }
    }

    // MARK: - Ghost control

    private var ghostModeControl: some View {
        Button {
            viewModel.presentGhostOptions()
        } label: {
            Image(systemName: viewModel.isCurrentUserGhost ? "location.slash.fill" : "location.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(viewModel.isCurrentUserGhost ? Color.secondary : Color.blue)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(viewModel.isCurrentUserGhost ? "位置已隐藏" : "位置共享设置")
    }

    // MARK: - Member list (bottom-right)

    private var memberListOverlay: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if viewModel.isMemberListExpanded {
                expandedMemberPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            memberListToggleButton
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isMemberListExpanded)
    }

    private var memberListToggleButton: some View {
        Button {
            viewModel.toggleMemberList()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(Color.blue)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())

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
        .accessibilityLabel(viewModel.isMemberListExpanded ? "收起家人列表" : "展开家人列表")
    }

    private var expandedMemberPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("家人位置")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.members) { member in
                        LocationMemberSheetRow(
                            member: member,
                            isSelected: viewModel.isSelected(memberID: member.id),
                            onSelectionChange: { selected in
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

    // MARK: - Helpers

    private func polylineSegments(for coordinates: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        guard coordinates.count >= 2 else { return [] }
        return zip(coordinates, coordinates.dropFirst()).map { [$0, $1] }
    }

    private func segmentStrokeColor(segmentIndex: Int, totalSegments: Int) -> Color {
        let progress = totalSegments > 0 ? Double(segmentIndex + 1) / Double(totalSegments) : 1
        return Color.blue.opacity(0.18 + (0.82 * progress))
    }

    private func fitCameraToDisplayedMembers() {
        let coordinates = viewModel.mapDisplayedMembers.flatMap(\.breadcrumbCoordinates)
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
    LocationMainView()
}
