import Foundation

#if canImport(Supabase)
import Supabase
#endif

struct SupabaseLocationTrailDataService: LocationTrailDataService {
    private static let tableName = "location_trail_segments"
    private static let selectColumns =
        "id,household_id,entity_id,started_at,ended_at,waypoints,point_count,created_at"
    /// 与服务端 RPC 保留策略对齐的默认拉取窗口。
    static let defaultRetention: TimeInterval = 48 * 60 * 60

    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func fetchTrailSegments(
        in householdId: UUID,
        since: Date? = nil
    ) async throws -> [LocationTrailSegment] {
        #if canImport(Supabase)
        let cutoff = since ?? Date().addingTimeInterval(-Self.defaultRetention)
        let rawResponse = try await provider.client
            .from(Self.tableName)
            .select(Self.selectColumns)
            .eq("household_id", value: householdId.uuidString.lowercased())
            .gte("ended_at", value: cutoff)
            .order("ended_at", ascending: false)
            .execute()
        return try decodeSegments(from: rawResponse.data)
        #else
        _ = householdId
        _ = since
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func fetchTrailSegments(
        householdId: UUID,
        entityId: UUID,
        since: Date? = nil
    ) async throws -> [LocationTrailSegment] {
        #if canImport(Supabase)
        let cutoff = since ?? Date().addingTimeInterval(-Self.defaultRetention)
        let rawResponse = try await provider.client
            .from(Self.tableName)
            .select(Self.selectColumns)
            .eq("household_id", value: householdId.uuidString.lowercased())
            .eq("entity_id", value: entityId.uuidString.lowercased())
            .gte("ended_at", value: cutoff)
            .order("ended_at", ascending: false)
            .execute()
        return try decodeSegments(from: rawResponse.data)
        #else
        _ = householdId
        _ = entityId
        _ = since
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    @discardableResult
    func uploadTrailSegment(
        householdId: UUID,
        entityId: UUID,
        startedAt: Date,
        endedAt: Date,
        waypoints: [TrailWaypoint]
    ) async throws -> LocationTrailSegment {
        #if canImport(Supabase)
        if LocationGhostPreferences.shouldSkipLocationUpload(householdId: householdId, profileId: entityId) {
            throw LocationTrailServiceError.skippedGhost
        }

        let params = PushLocationTrailSegmentParams(
            pHouseholdId: householdId,
            pEntityId: entityId,
            pStartedAt: startedAt,
            pEndedAt: endedAt,
            pWaypoints: waypoints
        )

        do {
            return try await provider.client
                .rpc("push_location_trail_segment", params: params)
                .execute()
                .value
        } catch {
            if isMissingRPC(error) {
                return try await insertDirectly(
                    householdId: householdId,
                    entityId: entityId,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    waypoints: waypoints
                )
            }
            throw error
        }
        #else
        _ = householdId
        _ = entityId
        _ = startedAt
        _ = endedAt
        _ = waypoints
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    #if canImport(Supabase)
    private func insertDirectly(
        householdId: UUID,
        entityId: UUID,
        startedAt: Date,
        endedAt: Date,
        waypoints: [TrailWaypoint]
    ) async throws -> LocationTrailSegment {
        let row = LocationTrailSegmentInsert(
            householdId: householdId,
            entityId: entityId,
            startedAt: startedAt,
            endedAt: endedAt,
            waypoints: waypoints,
            pointCount: waypoints.count
        )
        let inserted: LocationTrailSegment = try await provider.client
            .from(Self.tableName)
            .insert(row)
            .select(Self.selectColumns)
            .single()
            .execute()
            .value

        // 客户端兜底清理（RPC 未部署时）
        let cutoff = Date().addingTimeInterval(-Self.defaultRetention)
        _ = try? await provider.client
            .from(Self.tableName)
            .delete()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .eq("entity_id", value: entityId.uuidString.lowercased())
            .lt("ended_at", value: cutoff)
            .execute()

        return inserted
    }

    private func decodeSegments(from data: Data) throws -> [LocationTrailSegment] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let date = try? container.decode(Date.self) { return date }
            let raw = try container.decode(String.self)
            if let date = Self.iso8601Fractional.date(from: raw) { return date }
            if let date = Self.iso8601.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(raw)")
        }
        return try decoder.decode([LocationTrailSegment].self, from: data)
    }

    private func isMissingRPC(_ error: Error) -> Bool {
        let haystack = (String(describing: error) + " " + error.localizedDescription).lowercased()
        return haystack.contains("push_location_trail_segment") && haystack.contains("schema cache")
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    #endif
}

private struct LocationTrailSegmentInsert: Encodable, Sendable {
    let householdId: UUID
    let entityId: UUID
    let startedAt: Date
    let endedAt: Date
    let waypoints: [TrailWaypoint]
    let pointCount: Int

    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case entityId = "entity_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case waypoints
        case pointCount = "point_count"
    }
}

enum LocationTrailServiceError: Error, LocalizedError {
    case skippedGhost

    var errorDescription: String? {
        switch self {
        case .skippedGhost:
            return "Location ghost mode is enabled"
        }
    }
}
