import Foundation

enum LocationMemberAssembler {
    /// 将名册与 `location_states` 合并为地图成员行；**不做** active / 隐身等业务过滤（仅合并数据）。
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
        let profileIds = Set(mergedProfiles.map(\.id))
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

        for membership in roster.memberships {
            guard let profileId = membership.profileId else {
                let row = orphanMembershipRow(
                    membership,
                    householdId: householdId,
                    recordsByProfile: recordsByProfile,
                    currentMembershipId: currentMembershipId,
                    servedLocationProfileIds: &servedLocationProfileIds
                )
                members.append(row)
                continue
            }
            guard profileIds.contains(profileId) == false else { continue }
            members.append(
                orphanMembershipRow(
                    membership,
                    householdId: householdId,
                    recordsByProfile: recordsByProfile,
                    currentMembershipId: currentMembershipId,
                    servedLocationProfileIds: &servedLocationProfileIds
                )
            )
        }

        appendMembersForUnmappedLocationRecords(
            into: &members,
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

    private static func orphanMembershipRow(
        _ membership: HouseholdMembership,
        householdId: UUID,
        recordsByProfile: [UUID: LocationStateRecord],
        currentMembershipId: UUID?,
        servedLocationProfileIds: inout Set<UUID>
    ) -> UserLocationState {
        let record: LocationStateRecord?
        if let profile = membership.profile {
            record = resolveLocationRecord(
                profile: profile,
                membership: membership,
                recordsByProfile: recordsByProfile
            )
        } else if let profileId = membership.profileId {
            record = recordsByProfile[profileId]
        } else {
            record = nil
        }
        if let record {
            servedLocationProfileIds.insert(record.profileId)
        }
        return memberState(
            id: membership.id,
            householdId: householdId,
            displayName: membership.displayName(linkedProfile: membership.profile),
            profile: membership.profile,
            record: record,
            isVirtualMember: membership.userId == nil,
            currentMembershipId: currentMembershipId
        )
    }

    /// 库里有 `location_states` 但名册未挂上档案时，仍生成可展示成员行（避免地图只显示自己）。
    private static func appendMembersForUnmappedLocationRecords(
        into members: inout [UserLocationState],
        roster: HouseholdMemberRoster,
        recordsByProfile: [UUID: LocationStateRecord],
        servedLocationProfileIds: Set<UUID>,
        householdId: UUID,
        currentMembershipId: UUID?
    ) {
        let memberProfileIds = Set(roster.memberships.compactMap(\.profileId))
        for record in recordsByProfile.values {
            guard servedLocationProfileIds.contains(record.profileId) == false else { continue }
            guard record.currentLocation != nil else { continue }

            if let membership = roster.memberships.first(where: { $0.profileId == record.profileId }) {
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
                } else {
                    members.append(
                        memberState(
                            id: membership.id,
                            householdId: householdId,
                            displayName: membership.displayName(linkedProfile: membership.profile),
                            profile: membership.profile,
                            record: record,
                            isVirtualMember: membership.userId == nil,
                            currentMembershipId: currentMembershipId
                        )
                    )
                }
                continue
            }

            if memberProfileIds.contains(record.profileId) {
                continue
            }

            let profile = roster.profiles.first(where: { $0.id == record.profileId })
            members.append(
                memberState(
                    id: record.profileId,
                    householdId: householdId,
                    displayName: profile?.displayName ?? String(localized: "群组成员"),
                    profile: profile,
                    record: record,
                    isVirtualMember: profile?.isVirtualUser == true,
                    currentMembershipId: currentMembershipId
                )
            )
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
        let ghostProfileId = profile?.id ?? record?.profileId
        let isGhost: Bool
        if isVirtualMember {
            isGhost = false
        } else if id == currentMembershipId, let ghostProfileId {
            isGhost = LocationGhostPreferences.isEffectivelyGhost(
                databaseFlag: record?.isGhostMode == true,
                profileId: ghostProfileId
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
            householdId: record?.householdId ?? householdId,
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
