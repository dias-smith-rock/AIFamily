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
    /// newest-first；`locations[0]` 为最新位置。
    var locations: [LocationPayload]
    var addressDescription: String?
    var lastUpdatedAt: Date?
    var batteryLevel: Int
    var isCharging: Bool
    var isCurrentUser: Bool

    var currentLocation: LocationPayload? {
        get { locations.first }
        set {
            guard let newValue else {
                if locations.isEmpty == false {
                    locations.removeFirst()
                }
                return
            }
            if locations.isEmpty {
                locations = [newValue]
            } else {
                locations[0] = newValue
            }
        }
    }

    var isVisibleOnMap: Bool {
        isGhostMode == false && currentLocation != nil
    }

    /// 含虚拟成员（硬件定位器档案）；隐身成员不可勾选。
    var isSelectableOnMap: Bool {
        isGhostMode == false
    }

    /// 时间顺序：最旧 → 最新（用于轨迹与渐变折线）。
    var breadcrumbCoordinates: [CLLocationCoordinate2D] {
        locations.reversed().map(\.coordinate)
    }

    /// 地图上展示的最近 N 个位置点（newest-first 截取；不影响服务端存储）。
    func mapVisibleLocations(displayCount: Int) -> [LocationPayload] {
        Array(locations.prefix(LocationMapDisplayPreferences.normalizedCount(displayCount)))
    }

    /// 地图轨迹折线用坐标（最旧 → 最新）。
    func mapVisibleBreadcrumbCoordinates(displayCount: Int) -> [CLLocationCoordinate2D] {
        mapVisibleLocations(displayCount: displayCount).reversed().map(\.coordinate)
    }

    var clampedBatteryLevel: Int {
        min(100, max(0, batteryLevel))
    }

    /// 当前位置坐标携带的采集时间，否则回退行级 `updated_at`。
    var currentLocationUpdatedAt: Date? {
        currentLocation?.recordedAt ?? lastUpdatedAt
    }

    /// 超过阈值无新点：家长端展示「可能离线」（非 Live）。
    var isLikelyOffline: Bool {
        guard isGhostMode == false else { return false }
        return LocationStaleness.isLikelyOffline(lastUpdatedAt: currentLocationUpdatedAt)
    }
}

extension UserLocationState {
    static let previewHouseholdId = UUID(uuidString: "B2000000-0000-4000-8000-000000000099") ?? UUID()

    private static func previewLocations(
        current: LocationPayload,
        history1: LocationPayload?,
        history2: LocationPayload?
    ) -> [LocationPayload] {
        [current, history1, history2].compactMap { $0 }
    }

    static let previewHousehold: [UserLocationState] = [
        UserLocationState(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000001") ?? UUID(),
            householdId: previewHouseholdId,
            displayName: "王晓明",
            isVirtualMember: false,
            isGhostMode: false,
            locations: previewLocations(
                current: LocationPayload(
                    latitude: 31.2304,
                    longitude: 121.4737,
                    recordedAt: Date().addingTimeInterval(-12 * 60),
                    batteryLevel: 78,
                    isCharging: false
                ),
                history1: LocationPayload(
                    latitude: 31.2289,
                    longitude: 121.4698,
                    recordedAt: Date().addingTimeInterval(-38 * 60),
                    batteryLevel: 82,
                    isCharging: false
                ),
                history2: LocationPayload(
                    latitude: 31.2265,
                    longitude: 121.4652,
                    recordedAt: Date().addingTimeInterval(-72 * 60),
                    batteryLevel: 88,
                    isCharging: false
                )
            ),
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
            locations: previewLocations(
                current: LocationPayload(
                    latitude: 31.2240,
                    longitude: 121.4805,
                    recordedAt: Date().addingTimeInterval(-4 * 60),
                    batteryLevel: 19,
                    isCharging: false
                ),
                history1: LocationPayload(
                    latitude: 31.2218,
                    longitude: 121.4770,
                    recordedAt: Date().addingTimeInterval(-28 * 60),
                    batteryLevel: 24,
                    isCharging: false
                ),
                history2: LocationPayload(
                    latitude: 31.2195,
                    longitude: 121.4720,
                    recordedAt: Date().addingTimeInterval(-55 * 60),
                    batteryLevel: 31,
                    isCharging: false
                )
            ),
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
            locations: [LocationPayload(latitude: 31.2180, longitude: 121.4600)],
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
            locations: [],
            addressDescription: nil,
            lastUpdatedAt: nil,
            batteryLevel: 100,
            isCharging: false,
            isCurrentUser: false
        ),
    ]
}
