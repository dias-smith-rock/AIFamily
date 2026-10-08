import CoreLocation
import Foundation

/// 轨迹段稀疏锚点（上云用，字段精简）。
struct TrailWaypoint: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    var recordedAt: Date?

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lng"
        case recordedAt = "recorded_at"
    }

    init(latitude: Double, longitude: Double, recordedAt: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.recordedAt = recordedAt
    }

    init(coordinate: CLLocationCoordinate2D, recordedAt: Date = Date()) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.recordedAt = recordedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        recordedAt = try Self.decodeOptionalDate(container: container, key: .recordedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        if let recordedAt {
            try container.encode(Self.formatDate(recordedAt), forKey: .recordedAt)
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distanceMeters(to other: TrailWaypoint) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
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
        if let date = iso8601WithFractional.date(from: raw) { return date }
        return iso8601NoFractional.date(from: raw)
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
