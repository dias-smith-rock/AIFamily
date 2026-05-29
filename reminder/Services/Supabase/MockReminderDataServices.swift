import Foundation

// MARK: - Tasks

actor MockTaskDataService: TaskDataService {
    private var tasks: [FamilyTask] = FamilyTask.mockTasks

    func fetchTasks(in householdId: UUID) async throws -> [FamilyTask] {
        // Mock：与线上一致，不按 user id 过滤 involvedMemberIds（该数组为 membership id）。
        tasks
            .filter { $0.householdId == householdId }
            .sorted { lhs, rhs in
            (lhs.dueDate ?? lhs.createdAt) < (rhs.dueDate ?? rhs.createdAt)
            }
    }

    func createTask(_ task: FamilyTask) async throws -> FamilyTask {
        tasks.append(task)
        return task
    }

    func updateTask(_ task: FamilyTask) async throws -> FamilyTask {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            throw SupabaseServiceError.invalidResponse
        }
        tasks[index] = task
        return task
    }

    func patchTaskStatus(taskId: UUID, to status: TaskStatus) async throws -> FamilyTask {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
            throw SupabaseServiceError.invalidResponse
        }
        var row = tasks[index]
        row.status = status
        tasks[index] = row
        return row
    }

    func deleteTask(taskId: UUID) async throws {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
            throw SupabaseServiceError.invalidResponse
        }
        tasks.remove(at: index)
    }
}

// MARK: - Feedbacks

actor MockFeedbackDataService: FeedbackDataService {
    private var feedbacks: [Feedback] = Feedback.mockFeedbacks

    func fetchFeedbacks(in householdId: UUID, for taskId: UUID?) async throws -> [Feedback] {
        let householdScoped = feedbacks.filter { $0.householdId == householdId }
        let filtered = taskId.map { id in
            householdScoped.filter { $0.taskId == id }
        } ?? householdScoped

        return filtered.sorted { $0.createdAt > $1.createdAt }
    }

    func createFeedback(_ feedback: Feedback) async throws -> Feedback {
        feedbacks.append(feedback)
        return feedback
    }

    func markFeedbackAsRead(id: UUID, readerId: UUID) async throws {
        guard let index = feedbacks.firstIndex(where: { $0.id == id }) else {
            throw SupabaseServiceError.invalidResponse
        }
        feedbacks[index] = feedbacks[index].markingRead(by: readerId)
    }

    func createSystemFeedback(householdId: UUID, content: String, taskId: UUID?) async throws -> Feedback {
        let feedback = Feedback(
            id: UUID(),
            householdId: householdId,
            taskId: taskId ?? UUID(),
            senderId: nil,
            content: content,
            voiceUrl: nil,
            imageUrls: nil,
            readBy: nil,
            isDeleted: false,
            replyToId: nil,
            createdAt: Date(),
            updatedAt: nil,
            mediaClearedAt: nil
        )
        feedbacks.append(feedback)
        return feedback
    }
}

// MARK: - Memberships

enum MockHouseholdRosterBuilder {
    static func roster(
        for householdId: UUID,
        profiles sourceProfiles: [FamilyProfile],
        memberships sourceMemberships: [HouseholdMembership]
    ) -> HouseholdMemberRoster {
        let memberRows = sourceMemberships
            .filter { $0.householdId == householdId }
            .sorted { $0.createdAt < $1.createdAt }

        var profilesById: [UUID: FamilyProfile] = [:]

        for membership in memberRows {
            if let profileId = membership.profileId,
               let profile = sourceProfiles.first(where: { $0.id == profileId }) {
                let linked = memberRows.filter {
                    $0.profileId == profile.id || ($0.userId != nil && $0.userId == profile.userId)
                }
                var copy = profile
                copy.memberships = linked.isEmpty ? [membership] : linked
                profilesById[profile.id] = copy
            } else if let profileId = membership.profileId {
                profilesById[profileId] = FamilyProfile.syntheticPlaceholder(
                    from: membership,
                    profileId: profileId,
                    relatedMemberships: [membership]
                )
            }
        }

        for profile in sourceProfiles where profile.householdId == householdId {
            guard profilesById[profile.id] == nil else { continue }
            let linked = memberRows.filter {
                $0.profileId == profile.id || ($0.userId != nil && $0.userId == profile.userId)
            }
            var copy = profile
            copy.memberships = linked.isEmpty ? nil : linked
            profilesById[profile.id] = copy
        }

        let profiles = profilesById.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        return HouseholdMemberRoster(profiles: profiles, memberships: memberRows)
    }
}

actor MockHouseholdMembershipDataService: HouseholdMembershipDataService {
    private var members: [HouseholdMembership] = HouseholdMembership.mockMembers

    func fetchMemberRoster(in householdId: UUID, activeOnly: Bool = true) async throws -> HouseholdMemberRoster {
        let roster = MockHouseholdRosterBuilder.roster(
            for: householdId,
            profiles: FamilyProfile.mockProfiles,
            memberships: members
        )
        return activeOnly ? roster.filteredToActiveMembers(in: householdId) : roster
    }

    func fetchMemberships(in householdId: UUID) async throws -> [HouseholdMembership] {
        members
            .filter { $0.householdId == householdId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func createMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership {
        members.append(membership)
        return membership
    }

    func updateMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership {
        guard let index = members.firstIndex(where: { $0.id == membership.id }) else {
            throw SupabaseServiceError.invalidResponse
        }
        members[index] = membership
        return membership
    }

    func updateNickname(householdId: UUID, profileId: UUID, nickname: String) async throws {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw SupabaseServiceError.invalidResponse
        }
        guard let index = members.firstIndex(where: {
            $0.householdId == householdId && $0.profileId == profileId
        }) else {
            return
        }
        members[index].nickname = trimmed
    }

    func removeMember(householdId: UUID, userId: UUID) async throws {
        members.removeAll { $0.householdId == householdId && $0.userId == userId }
    }
}

// MARK: - Family Profiles

actor MockFamilyProfileDataService: FamilyProfileDataService {
    private var profiles: [FamilyProfile] = FamilyProfile.mockProfiles

    func fetchProfiles(in householdId: UUID) async throws -> [FamilyProfile] {
        MockHouseholdRosterBuilder.roster(
            for: householdId,
            profiles: profiles,
            memberships: HouseholdMembership.mockMembers
        ).profiles
    }

    func fetchProfile(id: UUID) async throws -> FamilyProfile? {
        guard let profile = profiles.first(where: { $0.id == id }) else { return nil }
        let memberRows = HouseholdMembership.mockMembers.filter {
            $0.profileId == profile.id || ($0.userId != nil && $0.userId == profile.userId)
        }
        var copy = profile
        copy.memberships = memberRows.isEmpty ? nil : memberRows
        return copy
    }

    func createLocalProfile(householdId: UUID, draft: LocalProfileDraft) async throws {
        let newProfile = FamilyProfile(
            id: UUID(),
            householdId: householdId,
            name: draft.name,
            userId: nil,
            avatarUrl: draft.avatarURL,
            gender: draft.gender,
            birthDate: draft.birthDate.map { Self.dateFormatter.string(from: $0) },
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
        profiles.append(newProfile)
    }

    func updateProfile(profileId: UUID, draft: LocalProfileDraft) async throws {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            throw SupabaseServiceError.invalidResponse
        }

        let normalized = draft.normalizedForProfileUpdate()
        profiles[index].name = normalized.name
        profiles[index].avatarUrl = normalized.avatarURL
        profiles[index].gender = normalized.gender
        profiles[index].birthDate = normalized.birthDate.map { Self.dateFormatter.string(from: $0) }
        profiles[index].idCardNum = normalized.idCardNum
        profiles[index].passportNum = normalized.passportNum
        profiles[index].permitNum = normalized.permitNum
        profiles[index].height = normalized.height
        profiles[index].weight = normalized.weight
        profiles[index].school = normalized.school
        profiles[index].grade = normalized.grade
        profiles[index].email = normalized.email
        profiles[index].mainPhone = normalized.mainPhone
        profiles[index].secondPhone = normalized.secondPhone
    }

    func deleteProfile(profileId: UUID) async throws {
        profiles.removeAll { $0.id == profileId }
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

// MARK: - Auth & Platform Mocks

actor MockAuthService: AuthService {
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
    }

    func sendMagicLink(email: String) async throws {
        _ = email
    }

    func sendPhoneOTP(phoneNumber: String) async throws {
        _ = phoneNumber
    }

    func signOut() async throws {}

    func hasValidSession() async -> Bool {
        true
    }

    func cleanUpCurrentUserAvatars() async {}

    func cleanUpProfileAvatar(profileId: UUID) async {
        _ = profileId
    }
}

actor MockVoiceStorageService: VoiceStorageService {
    func uploadVoiceFeedback(data: Data, fileName: String) async throws -> URL {
        _ = data
        return URL(string: "https://example.com/voice/\(fileName)") ?? URL(fileURLWithPath: "/tmp/\(fileName)")
    }

    func removeVoiceFiles(atPaths paths: [String]) async {
        _ = paths
    }
}

actor MockAvatarStorageService: AvatarStorageService {
    func uploadAvatarImage(data: Data, fileName: String) async throws -> URL {
        _ = data
        return URL(string: "https://example.com/avatar/\(fileName)") ?? URL(fileURLWithPath: "/tmp/\(fileName)")
    }

    func removeAvatarFiles(atPaths paths: [String]) async {
        _ = paths
    }
}

actor MockFeedbackRealtimeService: FeedbackRealtimeService {
    func subscribeToFeedbackInserts(onEvent: @escaping @Sendable (Feedback) -> Void) async throws {
        _ = onEvent
    }

    func unsubscribe() async {}
}

actor MockInviteLinkService: InviteLinkService {
    func generateSignedInviteLink(
        token: String,
        contactMethod: ContactMethod,
        expiresInSeconds: Int
    ) async throws -> URL {
        _ = expiresInSeconds
        return URL(string: "https://aifamily.app/invite/signed?token=\(token)&channel=\(contactMethod.rawValue)") ?? URL(fileURLWithPath: "/tmp/invite")
    }
}

actor MockHouseholdRoutingService: HouseholdRoutingService {
    func createHousehold(displayName: String, description: String?) async throws -> UUID {
        _ = displayName
        _ = description
        return UUID()
    }

    func joinHousehold(inviteCode: String) async throws {
        _ = inviteCode
    }

    func renameHousehold(householdId: UUID, newName: String, description: String) async throws {
        _ = householdId
        _ = newName
        _ = description
    }

    func fetchMyJoinedHouseholds() async throws -> [JoinedHousehold] {
        []
    }

    func leaveHousehold(householdId: UUID) async throws {
        _ = householdId
    }

    func disbandHousehold(id: UUID, expectedName: String) async throws {
        _ = id
        _ = expectedName
    }

    func cleanUpHouseholdFeedbackAudios(householdId: UUID) async {
        _ = householdId
    }

    func transferOwnership(householdId: UUID, newCreatorUserId: UUID) async throws {
        _ = householdId
        _ = newCreatorUserId
    }
}
