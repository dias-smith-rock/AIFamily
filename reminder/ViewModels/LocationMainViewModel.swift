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

    init(members: [UserLocationState] = UserLocationState.previewHousehold) {
        self.members = members
        self.selectedMemberIDs = Set(members.filter { $0.isGhostMode == false }.map(\.id))
    }

    var currentUser: UserLocationState? {
        members.first(where: \.isCurrentUser)
    }

    /// 已勾选且未隐身、有当前坐标的成员（地图轨迹与头像）。
    var mapDisplayedMembers: [UserLocationState] {
        members.filter { member in
            selectedMemberIDs.contains(member.id) && member.isVisibleOnMap
        }
    }

    var isCurrentUserGhost: Bool {
        currentUser?.isGhostMode == true
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

    func applyGhostOption(_ option: GhostModeOption) {
        guard let index = members.firstIndex(where: \.isCurrentUser) else { return }
        switch option {
        case .pauseOneHour, .untilTonight, .keepHidden:
            members[index].isGhostMode = true
            selectedMemberIDs.remove(members[index].id)
        case .stopHiding:
            members[index].isGhostMode = false
            selectedMemberIDs.insert(members[index].id)
        }
    }

    func presentGhostOptions() {
        isGhostOptionsPresented = true
    }
}
