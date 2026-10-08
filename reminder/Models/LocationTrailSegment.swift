import Foundation

/// `location_trail_segments` 一行：稀疏锚点行程段。
struct LocationTrailSegment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let householdId: UUID
    /// `family_profiles.id`
    let entityId: UUID
    let startedAt: Date
    let endedAt: Date
    /// 时间顺序：最旧 → 最新。
    let waypoints: [TrailWaypoint]
    let pointCount: Int
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case entityId = "entity_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case waypoints
        case pointCount = "point_count"
        case createdAt = "created_at"
    }

    init(
        id: UUID = UUID(),
        householdId: UUID,
        entityId: UUID,
        startedAt: Date,
        endedAt: Date,
        waypoints: [TrailWaypoint],
        pointCount: Int? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.householdId = householdId
        self.entityId = entityId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.waypoints = waypoints
        self.pointCount = pointCount ?? waypoints.count
        self.createdAt = createdAt
    }
}
