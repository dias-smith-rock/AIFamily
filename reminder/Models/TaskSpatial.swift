import Foundation

// MARK: - Geofence (tasks.geofence JSONB)

struct TaskGeofence: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let radius: Double
    let addressName: String
    let triggerType: String

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lng"
        case radius
        case addressName = "address_name"
        case triggerType = "trigger_type"
    }
}

// MARK: - Completion location (tasks.completion_location JSONB)

struct TaskCompletionLocation: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let completedAt: Date
    let completedBy: UUID

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lng"
        case completedAt = "completed_at"
        case completedBy = "completed_by"
    }
}

// MARK: - FamilyTask ↔ spatial payloads

extension FamilyTask.LocationData {
    /// 将现有 `location_data` 转为 RPC `p_geofence` 载荷；缺少坐标或名称时返回 `nil`。
    func toTaskGeofence(
        triggerType: String = "on_enter",
        radius: Double = 200
    ) -> TaskGeofence? {
        guard let lat = latitude, let lng = longitude else { return nil }
        let name = (name ?? address)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard name.isEmpty == false else { return nil }
        return TaskGeofence(
            latitude: lat,
            longitude: lng,
            radius: radius,
            addressName: name,
            triggerType: triggerType
        )
    }
}

extension TaskGeofence {
    func toLocationData() -> FamilyTask.LocationData {
        FamilyTask.LocationData(
            name: addressName,
            address: addressName,
            latitude: latitude,
            longitude: longitude
        )
    }
}