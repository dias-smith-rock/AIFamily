import CoreLocation
import Foundation

#if canImport(Supabase)
import Supabase
#endif

struct SupabaseLocationStateDataService: LocationStateDataService {
    static let defaultMinUpdateDistanceMeters: Double = 500
    private static let tableName = "location_states"

    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func fetchLocationStates(in householdId: UUID) async throws -> [LocationStateRecord] {
        #if canImport(Supabase)
        let response: [LocationStateRecord] = try await provider.client
            .from(Self.tableName)
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .execute()
            .value
        return response
        #else
        _ = householdId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func fetchLocationState(householdId: UUID, membershipId: UUID) async throws -> LocationStateRecord? {
        #if canImport(Supabase)
        let rows: [LocationStateRecord] = try await provider.client
            .from(Self.tableName)
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .eq("entity_id", value: membershipId.uuidString.lowercased())
            .limit(1)
            .execute()
            .value
        return rows.first
        #else
        _ = householdId
        _ = membershipId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    @discardableResult
    func reportCurrentLocationIfNeeded(
        householdId: UUID,
        membershipId: UUID,
        coordinate: LocationPayload,
        minDistanceMeters: Double
    ) async throws -> Bool {
        let existing = try await fetchLocationState(householdId: householdId, membershipId: membershipId)
        if LocationGhostPreferences.isEffectivelyGhost(
            databaseFlag: existing?.isGhostMode == true,
            membershipId: membershipId
        ) {
            return false
        }

        if let current = existing?.currentLocation,
           distanceMeters(from: current, to: coordinate) < minDistanceMeters {
            return false
        }

        #if canImport(Supabase)
        let params = PushEntityLocationParams(
            pEntityId: membershipId,
            pHouseholdId: householdId,
            pNewLocation: coordinate
        )
        do {
            _ = try await provider.client
                .rpc("push_entity_location", params: params)
                .execute()
            return true
        } catch where LocationStateRPCSupport.isMissingPushEntityLocationRPC(error) {
            let now = Date()
            let payload = LocationStateUpsertPayload(
                householdId: householdId,
                membershipId: membershipId,
                currentLocation: coordinate,
                historyLocation1: existing?.currentLocation,
                historyLocation2: existing?.historyLocation1,
                isGhostMode: existing?.isGhostMode ?? false,
                updatedAt: now
            )
            if existing == nil {
                _ = try await provider.client
                    .from(Self.tableName)
                    .insert(payload)
                    .execute()
            } else {
                _ = try await provider.client
                    .from(Self.tableName)
                    .update(payload)
                    .eq("entity_id", value: membershipId.uuidString.lowercased())
                    .eq("household_id", value: householdId.uuidString.lowercased())
                    .execute()
            }
            return true
        }
        #else
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func updateGhostMode(
        householdId: UUID,
        membershipId: UUID,
        isGhostMode: Bool
    ) async throws -> LocationStateRecord {
        #if canImport(Supabase)
        let patch = LocationStateGhostPatch(isGhostMode: isGhostMode, updatedAt: Date())
        if let existing = try await fetchLocationState(householdId: householdId, membershipId: membershipId) {
            let updated: LocationStateRecord = try await provider.client
                .from(Self.tableName)
                .update(patch)
                .eq("id", value: existing.id.uuidString.lowercased())
                .select()
                .single()
                .execute()
                .value
            return updated
        }

        let inserted: LocationStateRecord = try await provider.client
            .from(Self.tableName)
            .insert(
                LocationStateUpsertPayload(
                    householdId: householdId,
                    membershipId: membershipId,
                    currentLocation: nil,
                    historyLocation1: nil,
                    historyLocation2: nil,
                    isGhostMode: isGhostMode,
                    updatedAt: Date()
                )
            )
            .select()
            .single()
            .execute()
            .value
        return inserted
        #else
        _ = householdId
        _ = membershipId
        _ = isGhostMode
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    private func distanceMeters(from origin: LocationPayload, to destination: LocationPayload) -> CLLocationDistance {
        let a = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let b = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return a.distance(from: b)
    }
}

#if canImport(Supabase)

private struct LocationStateUpsertPayload: Encodable {
    let householdId: UUID
    let membershipId: UUID
    let currentLocation: LocationPayload?
    let historyLocation1: LocationPayload?
    let historyLocation2: LocationPayload?
    let isGhostMode: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case membershipId = "entity_id"
        case currentLocation = "current_location"
        case historyLocation1 = "history_location_1"
        case historyLocation2 = "history_location_2"
        case isGhostMode = "is_ghost_mode"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(membershipId, forKey: .membershipId)
        if let currentLocation {
            try container.encode(currentLocation, forKey: .currentLocation)
        } else {
            try container.encodeNil(forKey: .currentLocation)
        }
        if let historyLocation1 {
            try container.encode(historyLocation1, forKey: .historyLocation1)
        } else {
            try container.encodeNil(forKey: .historyLocation1)
        }
        if let historyLocation2 {
            try container.encode(historyLocation2, forKey: .historyLocation2)
        } else {
            try container.encodeNil(forKey: .historyLocation2)
        }
        try container.encode(isGhostMode, forKey: .isGhostMode)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct LocationStateGhostPatch: Encodable {
    let isGhostMode: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case isGhostMode = "is_ghost_mode"
        case updatedAt = "updated_at"
    }
}

#endif
