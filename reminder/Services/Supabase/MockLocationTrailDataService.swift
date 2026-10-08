import Foundation

actor MockLocationTrailDataService: LocationTrailDataService {
    private var segments: [LocationTrailSegment] = []

    func fetchTrailSegments(in householdId: UUID, since: Date?) async throws -> [LocationTrailSegment] {
        let cutoff = since ?? Date().addingTimeInterval(-SupabaseLocationTrailDataService.defaultRetention)
        return segments.filter { $0.householdId == householdId && $0.endedAt >= cutoff }
            .sorted { $0.endedAt > $1.endedAt }
    }

    func fetchTrailSegments(
        householdId: UUID,
        entityId: UUID,
        since: Date?
    ) async throws -> [LocationTrailSegment] {
        let all = try await fetchTrailSegments(in: householdId, since: since)
        return all.filter { $0.entityId == entityId }
    }

    @discardableResult
    func uploadTrailSegment(
        householdId: UUID,
        entityId: UUID,
        startedAt: Date,
        endedAt: Date,
        waypoints: [TrailWaypoint]
    ) async throws -> LocationTrailSegment {
        if LocationGhostPreferences.shouldSkipLocationUpload(householdId: householdId, profileId: entityId) {
            throw LocationTrailServiceError.skippedGhost
        }
        let segment = LocationTrailSegment(
            householdId: householdId,
            entityId: entityId,
            startedAt: startedAt,
            endedAt: endedAt,
            waypoints: waypoints
        )
        segments.insert(segment, at: 0)

        let cutoff = Date().addingTimeInterval(-SupabaseLocationTrailDataService.defaultRetention)
        segments.removeAll { $0.householdId == householdId && $0.entityId == entityId && $0.endedAt < cutoff }
        let forEntity = segments.filter { $0.householdId == householdId && $0.entityId == entityId }
        if forEntity.count > 20 {
            let keepIDs = Set(forEntity.prefix(20).map(\.id))
            segments.removeAll {
                $0.householdId == householdId && $0.entityId == entityId && keepIDs.contains($0.id) == false
            }
        }
        return segment
    }
}
