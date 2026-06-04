import CoreLocation
import Foundation

/// 群组成员在地图 Tab 的展示态（档案 + `location_states` 合并，供 UI / Mock）。
struct UserLocationState: Identifiable, Hashable, Sendable {
    let id: UUID
    /// 当前群组（`location_states.household_id`）；地图与上报均按此隔离。
    let householdId: UUID
    let displayName: String
    var avatarURL: URL?
    /// 无账号虚拟档案（`family_profiles`，无 `household_memberships` 行）。
    var isVirtualMember: Bool
    var isGhostMode: Bool
    var currentLocation: LocationPayload?
    var historyLocation1: LocationPayload?
    var historyLocation2: LocationPayload?
    var addressDescription: String?
    var lastUpdatedAt: Date?
    var batteryLevel: Int
    var isCharging: Bool
    var isCurrentUser: Bool

    var isVisibleOnMap: Bool {
        isGhostMode == false && currentLocation != nil
    }

    /// 含虚拟成员（硬件定位器档案）；隐身成员不可勾选。
    var isSelectableOnMap: Bool {
        isGhostMode == false
    }

    /// 时间顺序：最旧 → 最新（用于轨迹与渐变折线）。
    var breadcrumbCoordinates: [CLLocationCoordinate2D] {
        [historyLocation2, historyLocation1, currentLocation]
            .compactMap { $0?.coordinate }
    }

    var clampedBatteryLevel: Int {
        min(100, max(0, batteryLevel))
    }
}

extension UserLocationState {
    static let previewHouseholdId = UUID(uuidString: "B2000000-0000-4000-8000-000000000099") ?? UUID()

    static let previewHousehold: [UserLocationState] = [
        UserLocationState(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000001") ?? UUID(),
            householdId: previewHouseholdId,
            displayName: "王晓明",
            isVirtualMember: false,
            isGhostMode: false,
            currentLocation: LocationPayload(latitude: 31.2304, longitude: 121.4737),
            historyLocation1: LocationPayload(latitude: 31.2289, longitude: 121.4698),
            historyLocation2: LocationPayload(latitude: 31.2265, longitude: 121.4652),
            addressDescription: "上海市黄浦区外滩",
            lastUpdatedAt: Date().addingTimeInterval(-12 * 60),
            batteryLevel: 78,
            isCharging: false,
            isCurrentUser: true
        ),
        UserLocationState(
            id: UUID(uuidString: "A1000002-0000-4000-8000-000000000002") ?? UUID(),
            householdId: previewHouseholdId,
            displayName: "李雨桐",
            isVirtualMember: false,
            isGhostMode: false,
            currentLocation: LocationPayload(latitude: 31.2240, longitude: 121.4805),
            historyLocation1: LocationPayload(latitude: 31.2218, longitude: 121.4770),
            historyLocation2: LocationPayload(latitude: 31.2195, longitude: 121.4720),
            addressDescription: "上海市浦东新区陆家嘴",
            lastUpdatedAt: Date().addingTimeInterval(-4 * 60),
            batteryLevel: 19,
            isCharging: false,
            isCurrentUser: false
        ),
        UserLocationState(
            id: UUID(uuidString: "A1000003-0000-4000-8000-000000000003") ?? UUID(),
            householdId: previewHouseholdId,
            displayName: "陈奶奶",
            isVirtualMember: false,
            isGhostMode: true,
            currentLocation: LocationPayload(latitude: 31.2180, longitude: 121.4600),
            historyLocation1: nil,
            historyLocation2: nil,
            addressDescription: nil,
            lastUpdatedAt: Date().addingTimeInterval(-90 * 60),
            batteryLevel: 54,
            isCharging: true,
            isCurrentUser: false
        ),
        UserLocationState(
            id: UUID(uuidString: "A1000004-0000-4000-8000-000000000004") ?? UUID(),
            householdId: previewHouseholdId,
            displayName: "小宝（档案）",
            isVirtualMember: true,
            isGhostMode: false,
            currentLocation: nil,
            historyLocation1: nil,
            historyLocation2: nil,
            addressDescription: nil,
            lastUpdatedAt: nil,
            batteryLevel: 100,
            isCharging: false,
            isCurrentUser: false
        ),
    ]
}
