import Foundation

// MARK: - Tasks

actor GuestTaskDataService: TaskDataService {
    private let store: GuestWorkspaceStore

    init(store: GuestWorkspaceStore = .shared) {
        self.store = store
    }

    func fetchTasks(in householdId: UUID) async throws -> [FamilyTask] {
        let snapshot = await store.currentSnapshot()
        guard snapshot.householdId == householdId else { return [] }
        return snapshot.tasks.sorted { lhs, rhs in
            (lhs.dueDate ?? lhs.createdAt) < (rhs.dueDate ?? rhs.createdAt)
        }
    }

    func createTask(_ task: FamilyTask, geofence: TaskGeofence?) async throws -> FamilyTask {
        var stored = task.sanitizedForPersistence()
        stored.geofence = geofence ?? task.geofence ?? task.locationData?.toTaskGeofence()
        await store.mutate { snapshot in
            snapshot.tasks.append(stored)
        }
        return stored
    }

    func updateTask(_ task: FamilyTask) async throws -> FamilyTask {
        let stored = task.sanitizedForPersistence()
        await store.mutate { snapshot in
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == stored.id }) else {
                return
            }
            snapshot.tasks[index] = stored
        }
        guard let updated = try await fetchTasks(in: stored.householdId).first(where: { $0.id == stored.id }) else {
            throw SupabaseServiceError.invalidResponse
        }
        return updated
    }

    func patchTaskStatus(
        taskId: UUID,
        to status: TaskStatus,
        completionLocation: TaskCompletionLocation?,
        actingMembershipId: UUID?
    ) async throws -> FamilyTask {
        _ = actingMembershipId
        var result: FamilyTask?
        await store.mutate { snapshot in
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            snapshot.tasks[index].status = status
            if let completionLocation {
                snapshot.tasks[index].completionLocation = completionLocation
            }
            result = snapshot.tasks[index]
        }
        guard let result else {
            throw SupabaseServiceError.invalidResponse
        }
        return result
    }

    func deleteTask(taskId: UUID) async throws {
        await store.mutate { snapshot in
            snapshot.tasks.removeAll { $0.id == taskId }
        }
    }
}

// MARK: - Memberships

actor GuestMembershipDataService: HouseholdMembershipDataService {
    private let store: GuestWorkspaceStore

    init(store: GuestWorkspaceStore = .shared) {
        self.store = store
    }

    func fetchMemberRoster(in householdId: UUID, activeOnly: Bool = true) async throws -> HouseholdMemberRoster {
        let snapshot = await store.currentSnapshot()
        let roster = MockHouseholdRosterBuilder.roster(
            for: householdId,
            profiles: snapshot.profiles,
            memberships: snapshot.memberships
        )
        return activeOnly ? roster.filteredToActiveMembers(in: householdId) : roster
    }

    func fetchMemberships(in householdId: UUID) async throws -> [HouseholdMembership] {
        let snapshot = await store.currentSnapshot()
        return snapshot.memberships
            .filter { $0.householdId == householdId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func createMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership {
        await store.mutate { snapshot in
            snapshot.memberships.append(membership)
        }
        return membership
    }

    func updateMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership {
        await store.mutate { snapshot in
            guard let index = snapshot.memberships.firstIndex(where: { $0.id == membership.id }) else { return }
            snapshot.memberships[index] = membership
        }
        return membership
    }

    func updateNickname(householdId: UUID, profileId: UUID, nickname: String) async throws {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw SupabaseServiceError.invalidResponse
        }
        await store.mutate { snapshot in
            if let index = snapshot.memberships.firstIndex(where: {
                $0.householdId == householdId && $0.profileId == profileId
            }) {
                snapshot.memberships[index].nickname = trimmed
            }
            if let profileIndex = snapshot.profiles.firstIndex(where: { $0.id == profileId }) {
                snapshot.profiles[profileIndex].name = trimmed
            }
        }
    }

    func removeMember(householdId: UUID, userId: UUID) async throws {
        await store.mutate { snapshot in
            snapshot.memberships.removeAll { $0.householdId == householdId && $0.userId == userId }
        }
    }
}

// MARK: - Profiles

actor GuestProfileDataService: FamilyProfileDataService {
    private let store: GuestWorkspaceStore

    init(store: GuestWorkspaceStore = .shared) {
        self.store = store
    }

    func fetchProfiles(in householdId: UUID) async throws -> [FamilyProfile] {
        try await GuestMembershipDataService(store: store).fetchMemberRoster(in: householdId).profiles
    }

    func fetchProfile(id: UUID) async throws -> FamilyProfile? {
        let snapshot = await store.currentSnapshot()
        guard var profile = snapshot.profiles.first(where: { $0.id == id }) else { return nil }
        let memberRows = snapshot.memberships.filter {
            $0.profileId == profile.id || ($0.userId != nil && $0.userId == profile.userId)
        }
        profile.householdMemberships = memberRows.isEmpty ? nil : memberRows
        return profile
    }

    func createLocalProfile(householdId: UUID, draft: LocalProfileDraft) async throws {
        let newProfile = FamilyProfile(
            id: UUID(),
            householdId: householdId,
            name: draft.name,
            userId: nil,
            avatarUrl: draft.avatarURL,
            gender: draft.gender,
            birthDate: draft.birthDate.map { GuestProfileDataService.dateFormatter.string(from: $0) },
            idCardNum: draft.idCardNum,
            passportNum: draft.passportNum,
            permitNum: draft.permitNum,
            height: draft.height,
            weight: draft.weight,
            school: draft.school,
            grade: draft.grade,
            email: draft.email,
            mainPhone: draft.mainPhone,
            secondPhone: draft.secondPhone
        )
        await store.mutate { snapshot in
            snapshot.profiles.append(newProfile)
        }
    }

    func updateProfile(profileId: UUID, draft: LocalProfileDraft) async throws {
        let normalized = draft.normalizedForProfileUpdate()
        await store.mutate { snapshot in
            guard let index = snapshot.profiles.firstIndex(where: { $0.id == profileId }) else { return }
            snapshot.profiles[index].name = normalized.name
            snapshot.profiles[index].avatarUrl = normalized.avatarURL
            snapshot.profiles[index].gender = normalized.gender
            snapshot.profiles[index].birthDate = normalized.birthDate.map {
                GuestProfileDataService.dateFormatter.string(from: $0)
            }
            snapshot.profiles[index].idCardNum = normalized.idCardNum
            snapshot.profiles[index].passportNum = normalized.passportNum
            snapshot.profiles[index].permitNum = normalized.permitNum
            snapshot.profiles[index].height = normalized.height
            snapshot.profiles[index].weight = normalized.weight
            snapshot.profiles[index].school = normalized.school
            snapshot.profiles[index].grade = normalized.grade
            snapshot.profiles[index].email = normalized.email
            snapshot.profiles[index].mainPhone = normalized.mainPhone
            snapshot.profiles[index].secondPhone = normalized.secondPhone
        }
    }

    func deleteProfile(profileId: UUID) async throws {
        await store.mutate { snapshot in
            snapshot.profiles.removeAll { $0.id == profileId }
            snapshot.memberships.removeAll { $0.profileId == profileId }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Household Routing

struct GuestHouseholdRoutingService: HouseholdRoutingService {
    private let store: GuestWorkspaceStore

    init(store: GuestWorkspaceStore = .shared) {
        self.store = store
    }

    func createHousehold(displayName: String, description: String?) async throws -> UUID {
        throw GuestCapabilityError.requiresSignIn
    }

    func joinHousehold(inviteCode: String) async throws {
        _ = inviteCode
        throw GuestCapabilityError.requiresSignIn
    }

    func renameHousehold(householdId: UUID, newName: String, description: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw HouseholdRoutingError.invalidHouseholdName
        }
        await store.mutate { snapshot in
            guard snapshot.householdId == householdId else { return }
            snapshot.householdName = trimmed
            snapshot.householdDescription = description
        }
    }

    func fetchMyJoinedHouseholds() async throws -> [JoinedHousehold] {
        let snapshot = await store.currentSnapshot()
        return [
            JoinedHousehold(
                id: snapshot.membershipId,
                householdId: snapshot.householdId,
                profileId: snapshot.profileId,
                role: MembershipRole.creator.rawValue,
                household: HouseholdBasicInfo(
                    id: snapshot.householdId,
                    name: snapshot.householdName,
                    status: MembershipStatus.active.rawValue,
                    isPremium: false
                )
            )
        ]
    }

    func leaveHousehold(householdId: UUID) async throws {
        _ = householdId
        throw GuestCapabilityError.requiresSignIn
    }

    func disbandHousehold(id: UUID, expectedName: String) async throws {
        _ = id
        _ = expectedName
        throw GuestCapabilityError.requiresSignIn
    }

    func cleanUpHouseholdFeedbackAudios(householdId: UUID) async {}

    func transferOwnership(householdId: UUID, newCreatorUserId: UUID) async throws {
        _ = householdId
        _ = newCreatorUserId
        throw GuestCapabilityError.requiresSignIn
    }
}

// MARK: - Auth

actor GuestAuthService: AuthService {
    func signInWithApple(
        idToken: String,
        rawNonce: String,
        appleGivenName: String?,
        appleFamilyName: String?,
        appleEmail: String?
    ) async throws {
        _ = idToken
        _ = rawNonce
        _ = appleGivenName
        _ = appleFamilyName
        _ = appleEmail
        throw GuestCapabilityError.requiresSignIn
    }

    func sendMagicLink(email: String) async throws {
        _ = email
        throw GuestCapabilityError.requiresSignIn
    }

    func sendPhoneOTP(phoneNumber: String) async throws {
        _ = phoneNumber
        throw GuestCapabilityError.requiresSignIn
    }

    func signOut() async throws {
        GuestSessionStore.clear()
        await GuestWorkspaceStore.shared.reloadFromDisk()
    }

    func hasValidSession() async -> Bool {
        false
    }

    func cleanUpCurrentUserAvatars() async {}

    func cleanUpProfileAvatar(profileId: UUID) async {
        _ = profileId
    }
}
