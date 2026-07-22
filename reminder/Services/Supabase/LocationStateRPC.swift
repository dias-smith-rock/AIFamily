import Foundation

#if canImport(Supabase)

/// `push_entity_location`：`p_entity_id` = **`family_profiles.id`**（非 membership / user id）。
struct PushEntityLocationParams: Encodable, Sendable {
    let pEntityId: UUID
    let pHouseholdId: UUID
    let pNewLocation: LocationPayload
    let pMinDistanceMeters: Double
    let pMinIntervalSeconds: Double

    enum CodingKeys: String, CodingKey {
        case pEntityId = "p_entity_id"
        case pHouseholdId = "p_household_id"
        case pNewLocation = "p_new_location"
        case pMinDistanceMeters = "p_min_distance_meters"
        case pMinIntervalSeconds = "p_min_interval_seconds"
    }
}

enum LocationStateRPCSupport {
    static func isMissingPushEntityLocationRPC(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        let localized = error.localizedDescription.lowercased()
        let haystack = message + " " + localized
        return haystack.contains("push_entity_location") && haystack.contains("schema cache")
    }
}

/// `debug_replace_location_states`：DEBUG 灌数整表替换 locations。
struct DebugReplaceLocationStatesParams: Encodable, Sendable {
    let pHouseholdId: UUID
    let pEntityId: UUID
    let pLocations: [LocationPayload]
    let pIsGhostMode: Bool

    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pEntityId = "p_entity_id"
        case pLocations = "p_locations"
        case pIsGhostMode = "p_is_ghost_mode"
    }
}

#endif
