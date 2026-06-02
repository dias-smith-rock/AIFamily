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
        currentUser?.isGhostMode == true
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
            members = LocationMemberAssembler.buildMembers(
                roster: roster,
                locationRecords: locationRecords,
                currentMembershipId: currentMembershipId
            )
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
        isGhostOptionsPresented = true
    }

    func applyGhostOption(_ option: GhostModeOption) async {
        guard let householdId, let currentMembershipId else { return }

        switch option {
        case .pauseOneHour:
            LocationGhostPreferences.setHiddenUntil(
                Date().addingTimeInterval(3_600),
                for: currentMembershipId
            )
        case .untilTonight:
            LocationGhostPreferences.setHiddenUntil(endOfToday(), for: currentMembershipId)
        case .keepHidden:
            LocationGhostPreferences.setHiddenUntil(nil, for: currentMembershipId)
        case .stopHiding:
            LocationGhostPreferences.setHiddenUntil(nil, for: currentMembershipId)
        }

        let shouldGhost: Bool
        switch option {
        case .stopHiding:
            shouldGhost = false
        default:
            shouldGhost = true
        }

        do {
            _ = try await locationStateService.updateGhostMode(
                householdId: householdId,
                membershipId: currentMembershipId,
                isGhostMode: shouldGhost
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

    private func displayStateForMap(_ member: UserLocationState) -> UserLocationState {
        guard member.isCurrentUser, let live = currentUserLiveLocation else { return member }
        var updated = member
        updated.currentLocation = live
        return updated
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
