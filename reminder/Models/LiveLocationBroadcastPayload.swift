import Foundation

/// Realtime Live Huddle 频道广播载荷（不进数据库，仅内存秒级同步）。
struct LiveLocationBroadcastPayload: Codable, Hashable, Sendable {
    let membershipId: UUID
    let lat: Double
    let lng: Double
    /// 手机顶部朝向（真北顺时针角度，0–360）；旧客户端可省略。
    let headingDegrees: Double?
    let timestamp: Date
    let batteryLevel: Int
    let isCharging: Bool

    init(
        membershipId: UUID,
        lat: Double,
        lng: Double,
        headingDegrees: Double? = nil,
        timestamp: Date = Date(),
        batteryLevel: Int = 100,
        isCharging: Bool = false
    ) {
        self.membershipId = membershipId
        self.lat = lat
        self.lng = lng
        self.headingDegrees = headingDegrees
        self.timestamp = timestamp
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
    }
}
