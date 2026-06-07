import CoreLocation
import Foundation

#if canImport(Supabase)
import Supabase
#endif

struct SupabaseLocationStateDataService: LocationStateDataService {
    /// Release：500m；Debug：0m，便于验证入库链路。
    static let defaultMinUpdateDistanceMeters: Double = {
        #if DEBUG
        return 0
        #else
        return 500
        #endif
    }()
    private static let tableName = "location_states"
    /// 与线上一致：表可能无 `id` 列，仅选实际存在的字段。
    private static let selectColumns =
        "household_id,entity_id,current_location,history_location_1,history_location_2,is_ghost_mode,updated_at"

    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func fetchLocationStates(in householdId: UUID) async throws -> [LocationStateRecord] {
        #if canImport(Supabase)
        let rawResponse = try await provider.client
            .from(Self.tableName)
            .select(Self.selectColumns)
            .eq("household_id", value: householdId.uuidString.lowercased())
            .execute()
        return try Self.decodeLocationStateRows(from: rawResponse.data)
        #else
        _ = householdId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func fetchLocationState(householdId: UUID, profileId: UUID) async throws -> LocationStateRecord? {
        #if canImport(Supabase)
        let rawResponse = try await provider.client
            .from(Self.tableName)
            .select(Self.selectColumns)
            .eq("household_id", value: householdId.uuidString.lowercased())
            .eq("entity_id", value: profileId.uuidString.lowercased())
            .limit(1)
            .execute()
        let rows = try Self.decodeLocationStateRows(from: rawResponse.data)
        return rows.first
        #else
        _ = householdId
        _ = profileId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    @discardableResult
    func reportCurrentLocationIfNeeded(
        householdId: UUID,
        profileId: UUID,
        coordinate: LocationPayload,
        minDistanceMeters: Double
    ) async throws -> LocationPersistOutcome {
        let existing = try await fetchLocationStateForReport(
            householdId: householdId,
            profileId: profileId
        )
        if LocationGhostPreferences.isEffectivelyGhost(
            databaseFlag: existing?.isGhostMode == true,
            profileId: profileId
        ) {
            print(
                "[LocationPersist] skip write ghost mode "
                + String(format: "lat=%.6f lng=%.6f", coordinate.latitude, coordinate.longitude)
            )
            return .skippedGhost
        }

        let movedMeters: Double?
        if let current = existing?.currentLocation {
            let moved = coordinate.distanceMeters(to: current)
            movedMeters = moved
            if moved < minDistanceMeters {
                print(
                    "[LocationPersist] skip write moved=\(String(format: "%.1f", moved))m "
                        + "need≥\(String(format: "%.0f", minDistanceMeters))m "
                        + "(db current_location vs new) "
                        + String(format: "new lat=%.6f lng=%.6f", coordinate.latitude, coordinate.longitude)
                        + String(format: " db lat=%.6f lng=%.6f", current.latitude, current.longitude)
                )
                return .skippedWithinThreshold(distanceMeters: moved)
            }
        } else {
            movedMeters = nil
        }

        print(
            "[LocationPersist] writing to database "
                + "profile=\(profileId.uuidString.prefix(8)) "
                + "household=\(householdId.uuidString.prefix(8)) "
                + String(format: "lat=%.6f lng=%.6f", coordinate.latitude, coordinate.longitude)
                + (movedMeters.map { " moved=\(String(format: "%.1f", $0))m" } ?? " moved=first_write")
        )

        let battery = DeviceBatteryMonitor.readSnapshot()
        let stampedCoordinate = coordinate.stampingDeviceSnapshotIfNeeded(
            batteryLevel: battery.level,
            isCharging: battery.isCharging
        )

        #if canImport(Supabase)
        let params = PushEntityLocationParams(
            pEntityId: profileId,
            pHouseholdId: householdId,
            pNewLocation: stampedCoordinate,
            pMinDistanceMeters: minDistanceMeters
        )
        do {
            _ = try await provider.client
                .rpc("push_entity_location", params: params)
                .execute()
            print(
                "[LocationPersist] push_entity_location ok profile=\(profileId.uuidString.prefix(8)) "
                + "household=\(householdId.uuidString.prefix(8)) "
                + String(format: "lat=%.6f lng=%.6f", coordinate.latitude, coordinate.longitude)
            )
            return .persisted
        } catch {
            logLocationPersistDatabaseError(error)
            guard LocationStateRPCSupport.isMissingPushEntityLocationRPC(error) else {
                throw error
            }
            let now = Date()
            let payload = LocationStateUpsertPayload(
                householdId: householdId,
                profileId: profileId,
                currentLocation: stampedCoordinate,
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
                    .eq("entity_id", value: profileId.uuidString.lowercased())
                    .eq("household_id", value: householdId.uuidString.lowercased())
                    .execute()
            }
            print(
                "[LocationPersist] location_states \(existing == nil ? "insert" : "update") ok "
                    + "profile=\(profileId.uuidString.prefix(8)) "
                    + String(format: "lat=%.6f lng=%.6f", coordinate.latitude, coordinate.longitude)
            )
            return .persisted
        }
        #else
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func updateGhostMode(
        householdId: UUID,
        profileId: UUID,
        isGhostMode: Bool
    ) async throws -> LocationStateRecord {
        #if canImport(Supabase)
        let patch = LocationStateGhostPatch(isGhostMode: isGhostMode, updatedAt: Date())
        if let existing = try await fetchLocationState(householdId: householdId, profileId: profileId) {
            let rawResponse = try await provider.client
                .from(Self.tableName)
                .update(patch)
                .eq("household_id", value: householdId.uuidString.lowercased())
                .eq("entity_id", value: profileId.uuidString.lowercased())
                .select(Self.selectColumns)
                .single()
                .execute()
            let rows = try Self.decodeLocationStateRows(from: rawResponse.data)
            guard let updated = rows.first else {
                return existing
            }
            return updated
        }

        let insertResponse = try await provider.client
            .from(Self.tableName)
            .insert(
                LocationStateUpsertPayload(
                    householdId: householdId,
                    profileId: profileId,
                    currentLocation: nil,
                    historyLocation1: nil,
                    historyLocation2: nil,
                    isGhostMode: isGhostMode,
                    updatedAt: Date()
                )
            )
            .select(Self.selectColumns)
            .single()
            .execute()
        let inserted = try Self.decodeLocationStateRows(from: insertResponse.data)
        guard let row = inserted.first else {
            throw SupabaseServiceError.invalidResponse
        }
        return row
        #else
        _ = householdId
        _ = profileId
        _ = isGhostMode
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    /// 读库失败（常见：未执行 GRANT/RLS 迁移）时返回 `nil`，写入改走 `push_entity_location`。
    private func logLocationPersistDatabaseError(_ error: Error) {
        let message = error.localizedDescription.lowercased()
        if message.contains("fk_location_states_entity")
            || message.contains("foreign key constraint") {
            print(
                "[LocationPersist] FK error: entity_id must be family_profiles.id — "
                    + "run 20260602_location_states_profile_entity.sql on Supabase"
            )
        }
    }

    private func fetchLocationStateForReport(
        householdId: UUID,
        profileId: UUID
    ) async throws -> LocationStateRecord? {
        do {
            return try await fetchLocationState(householdId: householdId, profileId: profileId)
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("permission denied") {
                print(
                    "[LocationPersist] fetchLocationState denied (run 20260602_location_states_rls.sql); "
                        + "will try push_entity_location RPC"
                )
                if LocationGhostPreferences.isEffectivelyGhost(
                    databaseFlag: false,
                    profileId: profileId
                ) {
                    return nil
                }
                return nil
            }
            throw error
        }
    }

    private static func decodeLocationStateRows(from data: Data) throws -> [LocationStateRecord] {
        let decoder = locationStateDecoder()
        do {
            return try decoder.decode([LocationStateRecord].self, from: data)
        } catch {
            #if DEBUG
            if let rawJSON = String(data: data, encoding: .utf8) {
                print("[LocationPersist] location_states decode failed JSON:\n\(rawJSON)")
            }
            if let decodingError = error as? DecodingError {
                print("[LocationPersist] decoding detail: \(decodingError)")
            }
            #endif
            throw error
        }
    }

    private static func locationStateDecoder() -> JSONDecoder {
        SupabaseCodec.makeLiteralColumnDecoder()
    }
}

#if canImport(Supabase)

private struct LocationStateUpsertPayload: Encodable {
    let householdId: UUID
    let profileId: UUID
    let currentLocation: LocationPayload?
    let historyLocation1: LocationPayload?
    let historyLocation2: LocationPayload?
    let isGhostMode: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case profileId = "entity_id"
        case currentLocation = "current_location"
        case historyLocation1 = "history_location_1"
        case historyLocation2 = "history_location_2"
        case isGhostMode = "is_ghost_mode"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(profileId, forKey: .profileId)
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
