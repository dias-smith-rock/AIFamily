import Foundation

/// Live Huddle Presence 状态（仅存于 Realtime，不写数据库）。
/// 后进入者通过 `presence_state` sync 即可读到已在场成员的 `lat`/`lng`。
struct LiveHuddlePresencePayload: Codable, Hashable, Sendable {
    let userId: String
    let name: String
    let membershipId: String
    let status: String
    let lat: Double?
    let lng: Double?
    let headingDegrees: Double?
    let batteryLevel: Int?
    let isCharging: Bool?

    init(
        userId: UUID,
        displayName: String,
        membershipId: UUID,
        status: String = "active",
        lat: Double? = nil,
        lng: Double? = nil,
        headingDegrees: Double? = nil,
        batteryLevel: Int? = nil,
        isCharging: Bool? = nil
    ) {
        self.userId = userId.uuidString.lowercased()
        self.name = displayName
        self.membershipId = membershipId.uuidString.lowercased()
        self.status = status
        self.lat = lat
        self.lng = lng
        self.headingDegrees = headingDegrees
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case membershipId = "membership_id"
        case status
        case lat
        case lng
        case headingDegrees = "heading_degrees"
        case batteryLevel = "battery_level"
        case isCharging = "is_charging"
    }

    var membershipUUID: UUID? {
        UUID(uuidString: membershipId)
    }

    var hasCoordinate: Bool {
        lat != nil && lng != nil
    }
}

extension LiveHuddlePresencePayload {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let userIdString = try container.decodeIfPresent(String.self, forKey: .userId) {
            userId = userIdString
        } else if let userIdUUID = try container.decodeIfPresent(UUID.self, forKey: .userId) {
            userId = userIdUUID.uuidString.lowercased()
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.userId,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing user_id")
            )
        }

        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""

        if let membershipString = try container.decodeIfPresent(String.self, forKey: .membershipId) {
            membershipId = membershipString
        } else if let membershipUUID = try container.decodeIfPresent(UUID.self, forKey: .membershipId) {
            membershipId = membershipUUID.uuidString.lowercased()
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.membershipId,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing membership_id")
            )
        }

        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lng = try container.decodeIfPresent(Double.self, forKey: .lng)
        headingDegrees = try container.decodeIfPresent(Double.self, forKey: .headingDegrees)
        batteryLevel = try container.decodeIfPresent(Int.self, forKey: .batteryLevel)
        isCharging = try container.decodeIfPresent(Bool.self, forKey: .isCharging)
    }
}
