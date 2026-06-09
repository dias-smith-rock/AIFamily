import CoreLocation
import Foundation

/// `location_states` 与各位置 JSONB 字段中的单点坐标。
struct LocationPayload: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    var addressName: String?
    /// 该坐标写入 JSONB 时的客户端时间戳（`recorded_at`）。
    var recordedAt: Date?
    /// 写入时的设备电量（0–100）。
    var batteryLevel: Int?
    /// 写入时是否正在充电。
    var isCharging: Bool?

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lng"
        case addressName = "address_name"
        case recordedAt = "recorded_at"
        case batteryLevel = "battery_level"
        case isCharging = "is_charging"
    }

    init(
        latitude: Double,
        longitude: Double,
        addressName: String? = nil,
        recordedAt: Date? = nil,
        batteryLevel: Int? = nil,
        isCharging: Bool? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.addressName = addressName
        self.recordedAt = recordedAt
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        addressName = try container.decodeIfPresent(String.self, forKey: .addressName)
        recordedAt = try Self.decodeOptionalDate(container: container, key: .recordedAt)
        batteryLevel = try container.decodeIfPresent(Int.self, forKey: .batteryLevel)
        isCharging = try container.decodeIfPresent(Bool.self, forKey: .isCharging)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encodeIfPresent(addressName, forKey: .addressName)
        if let recordedAt {
            try container.encode(Self.formatDate(recordedAt), forKey: .recordedAt)
        }
        if let batteryLevel {
            try container.encode(min(100, max(0, batteryLevel)), forKey: .batteryLevel)
        }
        if let isCharging {
            try container.encode(isCharging, forKey: .isCharging)
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clampedBatteryLevel: Int? {
        batteryLevel.map { min(100, max(0, $0)) }
    }

    /// 与另一点的球面距离（米）；用于入库前与最新位置比对。
    func distanceMeters(to other: LocationPayload) -> CLLocationDistance {
        let origin = CLLocation(latitude: latitude, longitude: longitude)
        let destination = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return origin.distance(from: destination)
    }

    /// 写入前补全时间戳与电量快照，便于历史轨迹点展示相对时间与电量。
    func stampingDeviceSnapshotIfNeeded(
        at date: Date = Date(),
        batteryLevel: Int,
        isCharging: Bool
    ) -> LocationPayload {
        var copy = self
        if copy.recordedAt == nil {
            copy.recordedAt = date
        }
        if copy.batteryLevel == nil {
            copy.batteryLevel = min(100, max(0, batteryLevel))
        }
        if copy.isCharging == nil {
            copy.isCharging = isCharging
        }
        return copy
    }

    private static func decodeOptionalDate(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return parseDate(raw)
    }

    private static func parseDate(_ raw: String) -> Date? {
        if let date = iso8601WithFractional.date(from: raw) {
            return date
        }
        if let date = iso8601NoFractional.date(from: raw) {
            return date
        }
        return nil
    }

    private static func formatDate(_ value: Date) -> String {
        iso8601WithFractional.string(from: value)
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let iso8601NoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
