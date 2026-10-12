import Foundation

actor MockLocationTrailDataService: LocationTrailDataService {
    private var segments: [LocationTrailSegment] = []

    init(seedPreview: Bool = true) {
        guard seedPreview else { return }
        seedPreviewSegmentsIfNeeded()
    }

    private func seedPreviewSegmentsIfNeeded() {
        let householdId = UserLocationState.previewHouseholdId
        #if DEBUG
        let currentProfileId = LocationRoadSnapDemoData.previewCurrentUserMembershipId
        for demo in LocationRoadSnapDemoData.previewShanghaiSegments(
            householdId: householdId,
            profileId: currentProfileId
        ) {
            segments.append(demo)
        }
        #endif
        let now = Date()
        for member in UserLocationState.previewHousehold where member.isGhostMode == false && member.locations.count >= 2 {
            let ordered = member.locations.reversed()
            let waypoints = ordered.map {
                TrailWaypoint(
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    recordedAt: $0.recordedAt
                )
            }
            guard waypoints.count >= 2 else { continue }
            segments.append(
                LocationTrailSegment(
                    householdId: householdId,
                    entityId: member.id,
                    startedAt: waypoints.first?.recordedAt ?? now.addingTimeInterval(-3600),
                    endedAt: waypoints.last?.recordedAt ?? now,
                    waypoints: waypoints
                )
            )
        }
    }

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
