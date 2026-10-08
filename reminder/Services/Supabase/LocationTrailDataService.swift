import Foundation

protocol LocationTrailDataService: Sendable {
    func fetchTrailSegments(
        in householdId: UUID,
        since: Date?
    ) async throws -> [LocationTrailSegment]

    func fetchTrailSegments(
        householdId: UUID,
        entityId: UUID,
        since: Date?
    ) async throws -> [LocationTrailSegment]

    @discardableResult
    func uploadTrailSegment(
        householdId: UUID,
        entityId: UUID,
        startedAt: Date,
        endedAt: Date,
        waypoints: [TrailWaypoint]
    ) async throws -> LocationTrailSegment
}
