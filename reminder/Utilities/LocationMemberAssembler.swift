import Foundation

enum LocationMemberAssembler {
    /// 将名册与 `location_states` 合并为地图成员行；**不做** active / 隐身等业务过滤（仅合并数据）。
    static func buildMembers(
        roster: HouseholdMemberRoster,
        locationRecords: [LocationStateRecord],
        currentMembershipId: UUID?
    ) -> [UserLocationState] {
        let recordsByMembership = locationRecords.reduce(into: [UUID: LocationStateRecord]()) { partial, record in
            partial[record.membershipId] = record
        }

        let mergedProfiles = FamilyProfile.mergingMembershipRows(
            roster.profiles,
            memberships: roster.memberships
        )
        let profileIds = Set(mergedProfiles.map(\.id))

        var members: [UserLocationState] = mergedProfiles.map { profile in
            let membership = roster.memberships.first(where: { $0.profileId == profile.id })
                ?? profile.primaryMembership

            if let membership {
                return memberState(
                    id: membership.id,
                    displayName: membership.displayName(linkedProfile: profile),
                    profile: profile,
                    record: recordsByMembership[membership.id],
                    isVirtualMember: profile.isVirtualUser,
                    currentMembershipId: currentMembershipId
                )
            }

            return memberState(
                id: profile.id,
                displayName: profile.displayName,
                profile: profile,
                record: nil,
                isVirtualMember: profile.isVirtualUser,
                currentMembershipId: currentMembershipId
            )
        }

        for membership in roster.memberships {
            guard let profileId = membership.profileId else {
                members.append(orphanMembershipRow(membership, recordsByMembership: recordsByMembership, currentMembershipId: currentMembershipId))
                continue
            }
            guard profileIds.contains(profileId) == false else { continue }
            members.append(orphanMembershipRow(membership, recordsByMembership: recordsByMembership, currentMembershipId: currentMembershipId))
        }

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

    private static func orphanMembershipRow(
        _ membership: HouseholdMembership,
        recordsByMembership: [UUID: LocationStateRecord],
        currentMembershipId: UUID?
    ) -> UserLocationState {
        memberState(
            id: membership.id,
            displayName: membership.displayName(linkedProfile: membership.profile),
            profile: membership.profile,
            record: recordsByMembership[membership.id],
            isVirtualMember: membership.userId == nil,
            currentMembershipId: currentMembershipId
        )
    }

    private static func memberState(
        id: UUID,
        displayName: String,
        profile: FamilyProfile?,
        record: LocationStateRecord?,
        isVirtualMember: Bool,
        currentMembershipId: UUID?
    ) -> UserLocationState {
        let isGhost: Bool
        if isVirtualMember {
            isGhost = false
        } else if id == currentMembershipId {
            isGhost = LocationGhostPreferences.isEffectivelyGhost(
                databaseFlag: record?.isGhostMode == true,
                membershipId: id
            )
        } else {
            isGhost = LocationGhostPreferences.isGhostOnServer(record: record)
        }

        let avatarURLString = profile?.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatarURL = avatarURLString.flatMap { URL(string: $0) }

        let address = record?.currentLocation?.addressName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return UserLocationState(
            id: id,
            displayName: displayName,
            avatarURL: avatarURL,
            isVirtualMember: isVirtualMember,
            isGhostMode: isGhost,
            currentLocation: record?.currentLocation,
            historyLocation1: record?.historyLocation1,
            historyLocation2: record?.historyLocation2,
            addressDescription: address?.isEmpty == false ? address : nil,
            lastUpdatedAt: record?.updatedAt,
            batteryLevel: 100,
            isCharging: false,
            isCurrentUser: isVirtualMember == false && id == currentMembershipId
        )
    }
}
