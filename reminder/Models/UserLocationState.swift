import CoreLocation
import Foundation

/// 家庭成员在地图 Tab 的展示态（档案 + `location_states` 合并，供 UI / Mock）。
struct UserLocationState: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    var avatarURL: URL?
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
    static let previewHousehold: [UserLocationState] = [
        UserLocationState(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000001") ?? UUID(),
            displayName: "王晓明",
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
            displayName: "李雨桐",
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
            displayName: "陈奶奶",
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
    ]
}
