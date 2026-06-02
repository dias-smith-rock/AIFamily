import Foundation

enum LocationMemberAssembler {
    static func buildMembers(
        roster: HouseholdMemberRoster,
        locationRecords: [LocationStateRecord],
        currentMembershipId: UUID?
    ) -> [UserLocationState] {
        let recordsByMembership = Dictionary(
            uniqueKeysWithValues: locationRecords.map { ($0.membershipId, $0) }
        )

        return roster.memberships.compactMap { membership in
            guard membership.isActiveMembership() else { return nil }
            let record = recordsByMembership[membership.id]
            let profile = membership.profile
                ?? roster.profiles.first(where: { $0.id == membership.profileId })

            let isGhost = LocationGhostPreferences.isEffectivelyGhost(
                databaseFlag: record?.isGhostMode == true,
                membershipId: membership.id
            )

            let avatarURLString = profile?.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
            let avatarURL = avatarURLString.flatMap { URL(string: $0) }

            let address = record?.currentLocation?.addressName?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return UserLocationState(
                id: membership.id,
                displayName: membership.displayName(linkedProfile: profile),
                avatarURL: avatarURL,
                isGhostMode: isGhost,
                currentLocation: record?.currentLocation,
                historyLocation1: record?.historyLocation1,
                historyLocation2: record?.historyLocation2,
                addressDescription: address?.isEmpty == false ? address : nil,
                lastUpdatedAt: record?.updatedAt,
                batteryLevel: 100,
                isCharging: false,
                isCurrentUser: membership.id == currentMembershipId
            )
        }
        .sorted { lhs, rhs in
            if lhs.isCurrentUser != rhs.isCurrentUser {
                return lhs.isCurrentUser
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }
}
