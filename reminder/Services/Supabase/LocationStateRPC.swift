import Foundation

#if canImport(Supabase)

/// `push_entity_location`：`p_entity_id` = **`family_profiles.id`**（非 membership / user id）。
struct PushEntityLocationParams: Encodable, Sendable {
    let pEntityId: UUID
    let pHouseholdId: UUID
    let pNewLocation: LocationPayload

    enum CodingKeys: String, CodingKey {
        case pEntityId = "p_entity_id"
        case pHouseholdId = "p_household_id"
        case pNewLocation = "p_new_location"
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

#endif
