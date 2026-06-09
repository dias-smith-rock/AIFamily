import CoreLocation
import Foundation

/// 游客模式位置：以本机 GPS 为锚点，在同城范围内模拟其他成员位置（不写入固定中国城市坐标）。
actor GuestLocationStateDataService: LocationStateDataService {
    private let store: GuestWorkspaceStore
    private var records: [LocationStateRecord] = []
    private var anchorUsed: CLLocationCoordinate2D?

    init(store: GuestWorkspaceStore = .shared) {
        self.store = store
    }

    func fetchLocationStates(in householdId: UUID) async throws -> [LocationStateRecord] {
        _ = try await ensureSimulatedRecords(householdId: householdId)
        return records.filter { $0.householdId == householdId }
    }

    func fetchLocationState(householdId: UUID, profileId: UUID) async throws -> LocationStateRecord? {
        _ = try await ensureSimulatedRecords(householdId: householdId)
        return records.first { $0.householdId == householdId && $0.profileId == profileId }
    }

    @discardableResult
    func reportCurrentLocationIfNeeded(
        householdId: UUID,
        profileId: UUID,
        coordinate: LocationPayload,
        minDistanceMeters: Double,
        minIntervalSeconds: TimeInterval
    ) async throws -> LocationPersistOutcome {
        _ = try await ensureSimulatedRecords(householdId: householdId)

        if let index = records.firstIndex(where: { $0.profileId == profileId }) {
            var row = records[index]
            if LocationGhostPreferences.shouldSkipLocationUpload(householdId: householdId, profileId: profileId) {
                return .skippedGhost
            }
            if let skipOutcome = LocationPersistWriteGate.skipOutcomeIfNotEligible(
                newCoordinate: coordinate,
                storedLocations: row.locations,
                lastRecordUpdatedAt: row.updatedAt,
                minDistanceMeters: minDistanceMeters,
                minIntervalSeconds: minIntervalSeconds
            ) {
                return skipOutcome
            }
            let battery = DeviceBatteryMonitor.readSnapshot()
            let stamped = coordinate.stampingDeviceSnapshotIfNeeded(
                batteryLevel: battery.level,
                isCharging: battery.isCharging
            )
            row.locations = LocationHistoryLimits.prepending(stamped, to: row.locations)
            row.updatedAt = Date()
            records[index] = row
            return .persisted
        }

        records.append(
            LocationStateRecord(
                databaseId: UUID(),
                householdId: householdId,
                profileId: profileId,
                locations: {
                    let battery = DeviceBatteryMonitor.readSnapshot()
                    return [
                        coordinate.stampingDeviceSnapshotIfNeeded(
                            batteryLevel: battery.level,
                            isCharging: battery.isCharging
                        )
                    ]
                }(),
                isGhostMode: false,
                updatedAt: Date()
            )
        )
        return .persisted
    }

    func updateGhostMode(
        householdId: UUID,
        profileId: UUID,
        isGhostMode: Bool
    ) async throws -> LocationStateRecord {
        _ = try await ensureSimulatedRecords(householdId: householdId)

        if let index = records.firstIndex(where: { $0.profileId == profileId }) {
            var row = records[index]
            row.isGhostMode = isGhostMode
            row.updatedAt = Date()
            records[index] = row
            return row
        }

        let row = LocationStateRecord(
            databaseId: UUID(),
            householdId: householdId,
            profileId: profileId,
            locations: [],
            isGhostMode: isGhostMode,
            updatedAt: Date()
        )
        records.append(row)
        return row
    }

    // MARK: - Simulation

    @discardableResult
    private func ensureSimulatedRecords(householdId: UUID) async throws -> [LocationStateRecord] {
        let snapshot = await store.currentSnapshot()
        guard snapshot.householdId == householdId else { return [] }

        await ensureDemoProfiles(in: snapshot)

        guard let anchor = await resolveAnchor() else {
            records.removeAll { $0.householdId == householdId && GuestSessionStore.isLocationDemoProfileId($0.profileId) }
            return records.filter { $0.householdId == householdId }
        }

        if let anchorUsed,
           anchorUsed.distanceMeters(to: anchor) < 5_000,
           records.contains(where: { GuestSessionStore.isLocationDemoProfileId($0.profileId) }) {
            return records.filter { $0.householdId == householdId }
        }

        anchorUsed = anchor
        records.removeAll { $0.householdId == householdId && GuestSessionStore.isLocationDemoProfileId($0.profileId) }

        let templates = locationDemoTemplates()
        let now = Date()
        for template in templates {
            let remapped = template.templateLocations.compactMap {
                GuestLocationCoordinateMapper.remap($0, anchor: anchor)
            }
            records.append(
                LocationStateRecord(
                    databaseId: UUID(),
                    householdId: householdId,
                    profileId: template.profileId,
                    locations: remapped,
                    isGhostMode: false,
                    updatedAt: now
                )
            )
        }

        return records.filter { $0.householdId == householdId }
    }

    private func ensureDemoProfiles(in snapshot: GuestWorkspaceSnapshot) async {
        let householdId = snapshot.householdId
        let existingIds = Set(snapshot.profiles.map(\.id))
        let missing = GuestSessionStore.locationDemoProfiles(householdId: householdId)
            .filter { existingIds.contains($0.id) == false }
        guard missing.isEmpty == false else { return }

        await store.mutate { mutable in
            guard mutable.householdId == householdId else { return }
            for profile in missing {
                mutable.profiles.append(profile)
            }
        }
    }

    private func resolveAnchor() async -> CLLocationCoordinate2D? {
        let cached = await MainActor.run {
            LastKnownDeviceLocation.cachedCoordinate(maxAgeSeconds: 3_600)
        }
        if let cached { return cached }
        return await DeviceLocationFetcher.currentCoordinate(timeoutSeconds: 3)
    }

    private struct LocationDemoTemplate {
        let profileId: UUID
        let templateLocations: [LocationPayload]
    }

    private func locationDemoTemplates() -> [LocationDemoTemplate] {
        let preview = UserLocationState.previewHousehold
        let demoIds = [
            GuestSessionStore.locationDemoProfile1Id,
            GuestSessionStore.locationDemoProfile2Id,
        ]
        let templateMembers = [preview[safe: 1], preview[safe: 0]].compactMap { $0 }

        return zip(demoIds, templateMembers).map { profileId, member in
            LocationDemoTemplate(
                profileId: profileId,
                templateLocations: member.locations
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private extension CLLocationCoordinate2D {
    func distanceMeters(to other: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
