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
        var existing = feedbacks[index].readBy ?? []
        if existing.contains(readerId) == false {
            existing.append(readerId)
        }
        feedbacks[index].readBy = existing
    }
}

// MARK: - Memberships

actor MockHouseholdMembershipDataService: HouseholdMembershipDataService {
    private var members: [HouseholdMembership] = HouseholdMembership.mockMembers

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
}

// MARK: - Family Profiles

actor MockFamilyProfileDataService: FamilyProfileDataService {
    private var profiles: [FamilyProfile] = FamilyProfile.mockProfiles

    func fetchProfiles(in householdId: UUID) async throws -> [FamilyProfile] {
        let memberRows = HouseholdMembership.mockMembers.filter { $0.householdId == householdId }
        return profiles
            .filter { $0.householdId == householdId }
            .map { p in
                let linked = memberRows.filter { m in
                    m.householdId == p.householdId
                        && (m.profileId == p.id || (m.userId != nil && m.userId == p.userId))
                }
                var copy = p
                copy.memberships = linked.isEmpty ? nil : linked
                return copy
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func fetchProfile(id: UUID) async throws -> FamilyProfile? {
        guard let profile = profiles.first(where: { $0.id == id }) else { return nil }
        let memberRows = HouseholdMembership.mockMembers.filter { $0.householdId == profile.householdId }
        let linked = memberRows.filter { m in
            m.householdId == profile.householdId
                && (m.profileId == profile.id || (m.userId != nil && m.userId == profile.userId))
        }
        var copy = profile
        copy.memberships = linked.isEmpty ? nil : linked
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

        profiles[index].name = draft.name
        profiles[index].avatarUrl = draft.avatarURL
        profiles[index].gender = draft.gender
        profiles[index].birthDate = draft.birthDate.map { Self.dateFormatter.string(from: $0) }
        profiles[index].idCardNum = draft.idCardNum
        profiles[index].passportNum = draft.passportNum
        profiles[index].permitNum = draft.permitNum
        profiles[index].height = draft.height
        profiles[index].weight = draft.weight
        profiles[index].school = draft.school
        profiles[index].grade = draft.grade
        profiles[index].email = draft.email
        profiles[index].mainPhone = draft.mainPhone
        profiles[index].secondPhone = draft.secondPhone
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
}

actor MockVoiceStorageService: VoiceStorageService {
    func uploadVoiceFeedback(data: Data, fileName: String) async throws -> URL {
        _ = data
        return URL(string: "https://example.com/voice/\(fileName)") ?? URL(fileURLWithPath: "/tmp/\(fileName)")
    }
}

actor MockAvatarStorageService: AvatarStorageService {
    func uploadAvatarImage(data: Data, fileName: String) async throws -> URL {
        _ = data
        return URL(string: "https://example.com/avatar/\(fileName)") ?? URL(fileURLWithPath: "/tmp/\(fileName)")
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
    func createHousehold(displayName: String) async throws -> UUID {
        _ = displayName
        return UUID()
    }

    func joinHousehold(inviteCode: String) async throws {
        _ = inviteCode
    }

    func renameHousehold(householdId: UUID, newName: String) async throws {
        _ = householdId
        _ = newName
    }
}
