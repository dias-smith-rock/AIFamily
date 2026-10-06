import Foundation

enum LocationMemberAssembler {
    /// 将名册与 `location_states` 合并为地图成员行；只展示家庭成员列表中会出现的人。
    static func buildMembers(
        roster: HouseholdMemberRoster,
        locationRecords: [LocationStateRecord],
        householdId: UUID,
        currentMembershipId: UUID?
    ) -> [UserLocationState] {
        let recordsByProfile = locationRecords.reduce(into: [UUID: LocationStateRecord]()) { partial, record in
            partial[record.profileId] = record
        }

        let mergedProfiles = FamilyProfile.mergingMembershipRows(
            roster.profiles,
            memberships: roster.memberships
        )
        var servedLocationProfileIds = Set<UUID>()

        var members: [UserLocationState] = mergedProfiles.map { profile in
            let membership = roster.memberships.first(where: { $0.profileId == profile.id })
                ?? profile.primaryMembership

            if let membership {
                let record = resolveLocationRecord(
                    profile: profile,
                    membership: membership,
                    recordsByProfile: recordsByProfile
                )
                if let record {
                    servedLocationProfileIds.insert(record.profileId)
                }
                return memberState(
                    id: membership.id,
                    householdId: householdId,
                    displayName: membership.displayName(linkedProfile: profile),
                    profile: profile,
                    record: record,
                    isVirtualMember: profile.isVirtualUser,
                    currentMembershipId: currentMembershipId
                )
            }

            let record = resolveLocationRecord(
                profile: profile,
                membership: nil,
                recordsByProfile: recordsByProfile
            )
            if let record {
                servedLocationProfileIds.insert(record.profileId)
            }
            return memberState(
                id: profile.id,
                householdId: householdId,
                displayName: profile.displayName,
                profile: profile,
                record: record,
                isVirtualMember: profile.isVirtualUser,
                currentMembershipId: currentMembershipId
            )
        }

        attachLocationRecordsToExistingMembers(
            members: &members,
            roster: roster,
            recordsByProfile: recordsByProfile,
            servedLocationProfileIds: servedLocationProfileIds,
            householdId: householdId,
            currentMembershipId: currentMembershipId
        )

        return members.sorted { lhs, rhs in
            if lhs.isCurrentUser != rhs.isCurrentUser {
                return lhs.isCurrentUser
            }
            if lhs.isVirtualMember != rhs.isVirtualMember {
                return lhs.isVirtualMember == false
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func resolveLocationRecord(
        profile: FamilyProfile,
        membership: HouseholdMembership?,
        recordsByProfile: [UUID: LocationStateRecord]
    ) -> LocationStateRecord? {
        if let record = recordsByProfile[profile.id] {
            return record
        }
        if let membershipProfileId = membership?.profileId,
           membershipProfileId != profile.id,
           let record = recordsByProfile[membershipProfileId] {
            return record
        }
        if let nestedId = membership?.profile?.id,
           nestedId != profile.id,
           let record = recordsByProfile[nestedId] {
            return record
        }
        return nil
    }

    /// 名册已有行时补上位置；已退群/无档案的 `location_states` 不再单独占一行。
    private static func attachLocationRecordsToExistingMembers(
        members: inout [UserLocationState],
        roster: HouseholdMemberRoster,
        recordsByProfile: [UUID: LocationStateRecord],
        servedLocationProfileIds: Set<UUID>,
        householdId: UUID,
        currentMembershipId: UUID?
    ) {
        for record in recordsByProfile.values {
            guard servedLocationProfileIds.contains(record.profileId) == false else { continue }
            guard let membership = roster.memberships.first(where: { $0.profileId == record.profileId }) else {
                continue
            }
            if let index = members.firstIndex(where: { $0.id == membership.id }) {
                if members[index].currentLocation == nil {
                    members[index] = memberState(
                        id: membership.id,
                        householdId: householdId,
                        displayName: membership.displayName(linkedProfile: membership.profile),
                        profile: membership.profile,
                        record: record,
                        isVirtualMember: membership.userId == nil,
                        currentMembershipId: currentMembershipId
                    )
                }
            }
        }
    }

    private static func memberState(
        id: UUID,
        householdId: UUID,
        displayName: String,
        profile: FamilyProfile?,
        record: LocationStateRecord?,
        isVirtualMember: Bool,
        currentMembershipId: UUID?
    ) -> UserLocationState {
        let avatarURLString = profile?.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatarURL = avatarURLString.flatMap { URL(string: $0) }

        let address = record?.latestLocation?.addressName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return UserLocationState(
            id: id,
            householdId: record?.householdId ?? householdId,
            displayName: displayName,
            avatarURL: avatarURL,
            isVirtualMember: isVirtualMember,
            isGhostMode: false,
            locations: record?.locations ?? [],
            addressDescription: address?.isEmpty == false ? address : nil,
            lastUpdatedAt: record?.updatedAt,
            batteryLevel: 100,
            isCharging: false,
            isCurrentUser: isVirtualMember == false && id == currentMembershipId
        )
    }
}
