import CoreLocation
import Foundation

/// 将固定模板坐标（原预览数据）平移到用户当前城市锚点。
enum GuestLocationCoordinateMapper {
    /// 与 `UserLocationState.previewHousehold` 模板中心一致，用于计算相对偏移。
    private static let templateCentroid = CLLocationCoordinate2D(
        latitude: 31.224133,
        longitude: 121.471067
    )

    static func remap(_ template: CLLocationCoordinate2D, anchor: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let deltaLat = template.latitude - templateCentroid.latitude
        let deltaLon = template.longitude - templateCentroid.longitude
        return CLLocationCoordinate2D(
            latitude: anchor.latitude + deltaLat,
            longitude: anchor.longitude + deltaLon
        )
    }

    static func remap(_ payload: LocationPayload?, anchor: CLLocationCoordinate2D) -> LocationPayload? {
        guard let payload else { return nil }
        let coordinate = remap(payload.coordinate, anchor: anchor)
        return LocationPayload(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            addressName: nil,
            recordedAt: payload.recordedAt,
            batteryLevel: payload.batteryLevel,
            isCharging: payload.isCharging
        )
    }
}
