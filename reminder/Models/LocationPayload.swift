import CoreLocation
import Foundation

/// `location_states` 与各位置 JSONB 字段中的单点坐标。
struct LocationPayload: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    var addressName: String?

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lng"
        case addressName = "address_name"
    }

    init(latitude: Double, longitude: Double, addressName: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.addressName = addressName
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
