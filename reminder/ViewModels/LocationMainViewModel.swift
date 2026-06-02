import Combine
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
            selectedMemberIDs = Set(previewMembers.filter { $0.isGhostMode == false }.map(\.id))
        }
    }

    var currentUser: UserLocationState? {
        members.first(where: \.isCurrentUser)
    }

    var mapDisplayedMembers: [UserLocationState] {
        members.filter { member in
            selectedMemberIDs.contains(member.id) && member.isVisibleOnMap
        }
    }

    var isCurrentUserGhost: Bool {
        currentUser?.isGhostMode == true
    }

    func bind(householdId: UUID?, currentMembershipId: UUID?) {
        self.householdId = householdId
        self.currentMembershipId = currentMembershipId
    }

    func refresh() async {
        guard let householdId else {
            members = []
            selectedMemberIDs = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let rosterTask = membershipService.fetchMemberRoster(in: householdId, activeOnly: true)
            async let statesTask = locationStateService.fetchLocationStates(in: householdId)
            let roster = try await rosterTask
            let states = try await statesTask
            let merged = LocationMemberAssembler.buildMembers(
                roster: roster,
                locationRecords: states,
                currentMembershipId: currentMembershipId
            )
            members = merged
            reconcileSelectionAfterReload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isSelected(memberID: UUID) -> Bool {
        selectedMemberIDs.contains(memberID)
    }

    func setSelected(_ selected: Bool, for memberID: UUID) {
        guard let member = members.first(where: { $0.id == memberID }), member.isGhostMode == false else {
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
                await LocationStartupReporter.reportIfNeeded(
                    householdId: householdId,
                    membershipId: currentMembershipId,
                    locationStateService: locationStateService
                )
                await refresh()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reconcileSelectionAfterReload() {
        let selectableIDs = Set(members.filter { $0.isGhostMode == false }.map(\.id))
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
