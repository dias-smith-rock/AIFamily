import Foundation
#if canImport(Supabase)
import Supabase
#endif

enum GuestDataMigrationError: LocalizedError {
    case missingMembershipContext
    case householdCreationFailed

    var errorDescription: String? {
        switch self {
        case .missingMembershipContext:
            AppLocalized.localizedSync(L10n.Family.couldNotLoadMembershipAfterMigrationPlease)
        case .householdCreationFailed:
            AppLocalized.localizedSync(L10n.Family.failedToCreateCloudGroupCheckYourNetwork)
        }
    }
}

@MainActor
enum GuestDataMigrationService {
    struct MigrationResult {
        let householdId: UUID
        let taskCount: Int
    }

    enum TrialMigrationDecision: Equatable {
        case migrate
        case discardReturningUser
        case keepSnapshotRetryLater
    }

    static func evaluateTrialMigration() async -> TrialMigrationDecision {
        switch await userHasAnyHouseholdMembership() {
        case .some(true):
            .discardReturningUser
        case .some(false):
            .migrate
        case .none:
            .keepSnapshotRetryLater
        }
    }

    /// 老用户重新登录：清除本机试用快照，不写入云端。
    static func discardTrialSnapshotWithoutMigration() async {
        GuestSessionStore.clear()
        await GuestWorkspaceStore.shared.reloadFromDisk()
    }

    static func migrate(snapshot: GuestWorkspaceSnapshot, appRouter: AppRouter) async throws -> MigrationResult {
        let live = ReminderServiceContainer.live()
        let trimmedName = snapshot.householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        let householdName: String
        if trimmedName.isEmpty || GuestSessionStore.isDefaultGuestHouseholdName(trimmedName) {
            householdName = GuestSessionStore.localizedDefaultHouseholdName()
        } else {
            householdName = trimmedName
        }
        let description = snapshot.householdDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let newHouseholdId = try await live.householdRoutingService.createHousehold(
            displayName: householdName,
            description: description.isEmpty ? nil : description
        )

        appRouter.preferHouseholdOnNextRefresh(newHouseholdId)
        await appRouter.refreshStateFromBackend()

        guard
            let newMembershipId = appRouter.selectedMembershipId,
            appRouter.selectedHouseholdId == newHouseholdId
        else {
            throw GuestDataMigrationError.missingMembershipContext
        }

        var profileMap: [UUID: UUID] = [:]
        if let newProfileId = appRouter.selectedProfileId {
            profileMap[snapshot.profileId] = newProfileId
        }

        let virtualProfiles = snapshot.profiles.filter { profile in
            profile.id != snapshot.profileId && profile.isVirtualUser
        }

        for profile in virtualProfiles {
            let draft = LocalProfileDraft(
                name: GuestSessionStore.cloudMigrationSelfName(profile.name),
                avatarURL: profile.avatarUrl,
                gender: profile.gender,
                birthDate: profile.birthDate.flatMap { GuestMigrationDateParsing.date(from: $0) },
                idCardNum: profile.idCardNum,
                passportNum: profile.passportNum,
                permitNum: profile.permitNum,
                height: profile.height,
                weight: profile.weight,
                school: profile.school,
                grade: profile.grade,
                email: profile.email,
                mainPhone: profile.mainPhone,
                secondPhone: profile.secondPhone
            )
            try await live.familyProfileService.createLocalProfile(householdId: newHouseholdId, draft: draft)
        }

        let roster = try await live.membershipService.fetchMemberRoster(in: newHouseholdId, activeOnly: true)
        for guestProfile in virtualProfiles {
            let expectedName = GuestSessionStore.cloudMigrationSelfName(guestProfile.name)
            if let match = roster.profiles.first(where: {
                $0.name == expectedName && $0.isVirtualUser
            }) {
                profileMap[guestProfile.id] = match.id
            }
        }

        let membershipMap: [UUID: UUID] = [snapshot.membershipId: newMembershipId]

        var migratedCount = 0
        for task in snapshot.tasks {
            let remapped = remapTask(
                task,
                newHouseholdId: newHouseholdId,
                newMembershipId: newMembershipId,
                membershipMap: membershipMap,
                profileMap: profileMap
            )
            _ = try await live.taskService.createTask(remapped, geofence: remapped.geofence)
            migratedCount += 1
        }

        GuestSessionStore.clear()
        await GuestWorkspaceStore.shared.reloadFromDisk()
        AnalyticsManager.log(event: .guestMigrated(taskCount: migratedCount))

        return MigrationResult(householdId: newHouseholdId, taskCount: migratedCount)
    }

    private static func remapTask(
        _ task: FamilyTask,
        newHouseholdId: UUID,
        newMembershipId: UUID,
        membershipMap: [UUID: UUID],
        profileMap: [UUID: UUID]
    ) -> FamilyTask {
        let remappedInvolved = task.involvedMemberIds?.map { membershipMap[$0] ?? newMembershipId }
        let remappedTargets = task.targetProfileIds?.compactMap { profileMap[$0] }
        let remappedLegacyTarget = task.targetProfileId.flatMap { profileMap[$0] }

        let remapped = FamilyTask(
            id: task.id,
            householdId: newHouseholdId,
            creatorId: membershipMap[task.creatorId] ?? newMembershipId,
            parentTaskId: task.parentTaskId,
            groupId: task.groupId,
            originalDueDate: task.originalDueDate,
            involvedMemberIds: remappedInvolved,
            targetProfileId: remappedLegacyTarget,
            targetProfileIds: remappedTargets,
            targetSubject: task.targetSubject,
            title: task.title,
            description: task.description,
            originalPrompt: task.originalPrompt,
            attachmentUrls: nil,
            externalContacts: task.externalContacts,
            locationData: task.locationData,
            geofence: task.geofence,
            completionLocation: task.completionLocation,
            externalSyncRefs: task.externalSyncRefs,
            alarmSetBy: task.alarmSetBy,
            status: task.status,
            priority: task.priority,
            source: task.source,
            taskType: task.taskType,
            dueDate: task.dueDate,
            endDatetime: task.endDatetime,
            durationMinutes: task.durationMinutes,
            isAllDay: task.isAllDay,
            recurrenceRule: task.recurrenceRule,
            recurrenceEndDate: task.recurrenceEndDate,
            issue: task.issue,
            recurrenceInterval: task.recurrenceInterval,
            reminderOffsets: task.reminderOffsets,
            estimatedCost: task.estimatedCost,
            backgroundColor: task.backgroundColor,
            emergencyPhone: task.emergencyPhone,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
        return remapped.sanitizedForPersistence()
    }

    #if canImport(Supabase)
    private struct MembershipProbe: Decodable {
        let id: UUID
    }

    /// `true` = 已有成员关系；`false` = 确认为新账号；`nil` = 查询失败。
    private static func userHasAnyHouseholdMembership() async -> Bool? {
        do {
            let client = SupabaseManager.shared.client
            let userId = try await client.auth.session.user.id
            let rows: [MembershipProbe] = try await client
                .from("household_memberships")
                .select("id")
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.isEmpty == false
        } catch {
            CrashReporting.record(error, context: ["step": "guest_migration_eligibility"])
            return nil
        }
    }
    #else
    private static func userHasAnyHouseholdMembership() async -> Bool? {
        false
    }
    #endif
}

private enum GuestMigrationDateParsing {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
