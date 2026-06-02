import CoreLocation
import Foundation

/// `location_states` 与各位置 JSONB 字段中的单点坐标。
struct LocationPayload: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lng"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
