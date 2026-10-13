import Foundation

#if canImport(Supabase)

struct ListLocationTrailSegmentsParams: Encodable, Sendable {
    let pHouseholdId: UUID
    let pSince: Date
    let pEntityId: UUID?

    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pSince = "p_since"
        case pEntityId = "p_entity_id"
    }
}

struct PushLocationTrailSegmentParams: Encodable, Sendable {
    let pHouseholdId: UUID
    let pEntityId: UUID
    let pStartedAt: Date
    let pEndedAt: Date
    let pWaypoints: [TrailWaypoint]

    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pEntityId = "p_entity_id"
        case pStartedAt = "p_started_at"
        case pEndedAt = "p_ended_at"
        case pWaypoints = "p_waypoints"
    }
}

#endif
