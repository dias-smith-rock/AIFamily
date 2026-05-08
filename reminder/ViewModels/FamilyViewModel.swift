import Foundation
import Combine
import SwiftUI

@MainActor
final class FamilyViewModel: ObservableObject {
    @Published private(set) var profiles: [FamilyProfile] = []
    @Published private(set) var orderedProfiles: [FamilyProfile] = []
    @Published private(set) var members: [HouseholdMembership] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var requiresLogin = false

    private let profileService: FamilyProfileDataService
    private let membershipService: HouseholdMembershipDataService
    private let taskService: TaskDataService
    private let avatarStorageService: AvatarStorageService
    private let inviteLinkService: InviteLinkService
    private let authService: AuthService
    private let householdRoutingService: HouseholdRoutingService
    private var currentHouseholdId: UUID?
    private var currentMembershipId: UUID?

    init(
        profileService: FamilyProfileDataService,
        membershipService: HouseholdMembershipDataService,
        taskService: TaskDataService,
        avatarStorageService: AvatarStorageService,
        inviteLinkService: InviteLinkService,
        authService: AuthService,
        householdRoutingService: HouseholdRoutingService
    ) {
        self.profileService = profileService
        self.membershipService = membershipService
        self.taskService = taskService
        self.avatarStorageService = avatarStorageService
        self.inviteLinkService = inviteLinkService
        self.authService = authService
        self.householdRoutingService = householdRoutingService
    }

    func setHouseholdContext(_ householdId: UUID?) {
        currentHouseholdId = householdId
    }

    func setMembershipContext(_ membershipId: UUID?) {
        currentMembershipId = membershipId
    }

    func loadMembers() async {
        #if DEBUG
        print("🔎 [FamilyDebug] loadMembers start - householdId=\(currentHouseholdId?.uuidString ?? "nil"), membershipId=\(currentMembershipId?.uuidString ?? "nil")")
        #endif
        let hasSession = await authService.hasValidSession()
        guard hasSession else {
            requiresLogin = true
            errorMessage = nil
            profiles = []
            orderedProfiles = []
            members = []
            hasLoadedOnce = true
            #if DEBUG
            print("🔎 [FamilyDebug] loadMembers aborted - invalid session")
            #endif
            return
        }

        guard let householdId = currentHouseholdId else {
            requiresLogin = false
            errorMessage = "当前未选择家庭。"
            profiles = []
            orderedProfiles = []
            members = []
            hasLoadedOnce = true
            #if DEBUG
            print("🔎 [FamilyDebug] loadMembers aborted - no household selected")
            #endif
            return
        }

        requiresLogin = false
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            async let profileRows = profileService.fetchProfiles(in: householdId)
            async let membershipRows = membershipService.fetchMemberships(in: householdId)
            let (p, m) = try await (profileRows, membershipRows)
            profiles = p
            members = m
            applyLocalOrdering()
            #if DEBUG
            print("✅ [FamilyDebug] loadMembers success - profiles=\(p.count), memberships=\(m.count)")
            #endif
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("❌ [FamilyDebug] loadMembers failed - \(error.localizedDescription)")
            #endif
        }
    }

    func didLoginSuccessfully() async {
        requiresLogin = false
        await loadMembers()
    }

    @discardableResult
    func createMember(_ member: HouseholdMembership) async -> HouseholdMembership? {
        guard let householdId = currentHouseholdId else {
            errorMessage = "当前未选择家庭。"
            return nil
        }
        guard member.householdId == householdId else {
            errorMessage = "成员创建失败：家庭上下文不一致。"
            return nil
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let createdMember = try await membershipService.createMembership(member)
            members.append(createdMember)
            members.sort { $0.createdAt < $1.createdAt }
            return createdMember
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createManagedProfile(householdId: UUID, draft: ManagedProfileDraft) async -> String? {
        var normalizedDraft = draft
        let stableName = String(draft.name)
        let normalizedName = stableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            return "请输入角色称呼（不能为空）。"
        }
        normalizedDraft.name = normalizedName

        setHouseholdContext(householdId)

        do {
            try await profileService.createManagedProfile(
                householdId: householdId,
                draft: normalizedDraft
            )
            if normalizedDraft.birthDate != nil {
                await createBirthdayTasksIfNeeded(
                    profileName: normalizedDraft.name,
                    draft: normalizedDraft,
                    householdId: householdId
                )
            }
            await loadMembers()
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return error.localizedDescription
        }
    }

    func updateProfile(_ profile: FamilyProfile, draft: ManagedProfileDraft) async -> String? {
        let originalBirthDate = profile.birthDate
        var normalizedDraft = draft
        normalizedDraft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedDraft.name.isEmpty == false else {
            return "称呼不能为空。"
        }

        guard canEditProfile(profile) else {
            return "当前没有权限修改该成员资料。"
        }

        do {
            try await profileService.updateProfile(profileId: profile.id, draft: normalizedDraft)
            if shouldCreateBirthdayAutomation(oldBirthDate: originalBirthDate, newBirthDate: normalizedDraft.birthDate) {
                await createBirthdayTasksIfNeeded(
                    profileName: normalizedDraft.name,
                    draft: normalizedDraft,
                    householdId: profile.householdId
                )
            }
            var updatedProfile = profile
            updatedProfile.name = normalizedDraft.name
            updatedProfile.avatarUrl = normalizedDraft.avatarURL
            updatedProfile.gender = normalizedDraft.gender
            updatedProfile.birthDate = normalizedDraft.birthDate.map { Self.profileDateFormatter.string(from: $0) }
            updatedProfile.idCardNum = normalizedDraft.idCardNum
            updatedProfile.passportNum = normalizedDraft.passportNum
            updatedProfile.permitNum = normalizedDraft.permitNum
            updatedProfile.height = normalizedDraft.height
            updatedProfile.weight = normalizedDraft.weight
            updatedProfile.school = normalizedDraft.school
            updatedProfile.grade = normalizedDraft.grade

            if let index = profiles.firstIndex(where: { $0.id == updatedProfile.id }) {
                profiles[index] = updatedProfile
            } else {
                profiles.append(updatedProfile)
            }
            applyLocalOrdering()
            errorMessage = nil
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return error.localizedDescription
        }
    }

    func uploadAvatar(data: Data, profileId: UUID?) async -> URL? {
        #if DEBUG
        print("🔎 [FamilyDebug] uploadAvatar received bytes=\(data.count)")
        #endif
        guard data.isEmpty == false else {
            errorMessage = "头像数据为空，请重新选择图片后再试。"
            #if DEBUG
            print("❌ [FamilyDebug] uploadAvatar aborted - empty data")
            #endif
            return nil
        }

        let fallbackUUID = UUID().uuidString.lowercased()
        let profileIdentifier: String
        if let profileId {
            profileIdentifier = profileId.uuidString.lowercased()
        } else {
            profileIdentifier = fallbackUUID
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = profileIdentifier + "-" + String(timestamp) + ".jpg"

        #if DEBUG
        print("📤 [FamilyDebug] uploadAvatar start - profileId=\(profileIdentifier), bytes=\(data.count), fileName=\(fileName)")
        #endif
        do {
            return try await avatarStorageService.uploadAvatarImage(data: data, fileName: fileName)
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("❌ [FamilyDebug] uploadAvatar failed - \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    func canEditProfile(_ profile: FamilyProfile?) -> Bool {
        guard let profile else { return canCurrentUserManageHousehold }
        guard let currentUserId = currentMembership?.userId else { return false }
        if profile.userId == currentUserId { return true }
        if canCurrentUserManageHousehold, profile.userId == nil { return true }
        return false
    }

    var currentUserProfile: FamilyProfile? {
        guard let currentUserId = currentMembership?.userId else { return nil }
        return profiles.first(where: { $0.userId == currentUserId })
    }

    var otherProfiles: [FamilyProfile] {
        guard let me = currentUserProfile else { return orderedProfiles }
        return orderedProfiles.filter { $0.id != me.id }
    }

    func moveOtherProfiles(fromOffsets source: IndexSet, toOffset destination: Int) {
        var others = otherProfiles
        others.move(fromOffsets: source, toOffset: destination)
        let me = currentUserProfile
        orderedProfiles = (me.map { [$0] } ?? []) + others
        persistOrder(for: others)
    }

    /// 影子成员的邀请链接以 `membership.id` 作为 token。
    func generateSignedInviteLink(for member: HouseholdMembership) async -> URL? {
        let token = "invite-\(member.id.uuidString.lowercased())"
        do {
            return try await inviteLinkService.generateSignedInviteLink(
                token: token,
                contactMethod: member.contactMethod,
                expiresInSeconds: 900
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateMember(_ member: HouseholdMembership) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let updatedMember = try await membershipService.updateMembership(member)
            guard let index = members.firstIndex(where: { $0.id == updatedMember.id }) else {
                await loadMembers()
                return
            }
            members[index] = updatedMember
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameHousehold(householdId: UUID, newName: String) async -> String? {
        let stableName = String(newName)
        let normalizedName = stableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            return "家庭名称不能为空。"
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await householdRoutingService.renameHousehold(
                householdId: householdId,
                newName: normalizedName
            )
            return nil
        } catch let error as HouseholdRoutingError {
            return mapHouseholdRenameError(error)
        } catch {
            return error.localizedDescription
        }
    }

    private var currentMembership: HouseholdMembership? {
        guard let currentMembershipId else { return nil }
        return members.first(where: { $0.id == currentMembershipId })
    }

    private var canCurrentUserManageHousehold: Bool {
        switch currentMembership?.role {
        case .creator, .admin:
            return true
        case .member, .none:
            return false
        }
    }

    private func applyLocalOrdering() {
        guard let householdId = currentHouseholdId else {
            orderedProfiles = profiles
            return
        }
        let me = currentUserProfile
        let savedOrder = loadPersistedOrder(householdId: householdId)
        let orderMap = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($1, $0) })
        let meId = me?.id
        let others = profiles
            .filter { $0.id != meId }
            .sorted { lhs, rhs in
                let left = orderMap[lhs.id] ?? Int.max
                let right = orderMap[rhs.id] ?? Int.max
                if left != right { return left < right }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        orderedProfiles = (me.map { [$0] } ?? []) + others
    }

    private func persistOrder(for others: [FamilyProfile]) {
        guard let householdId = currentHouseholdId else { return }
        let ids = others.map(\.id.uuidString)
        UserDefaults.standard.set(ids, forKey: orderStorageKey(householdId: householdId))
    }

    private func loadPersistedOrder(householdId: UUID) -> [UUID] {
        let raw = UserDefaults.standard.array(forKey: orderStorageKey(householdId: householdId)) as? [String] ?? []
        return raw.compactMap(UUID.init(uuidString:))
    }

    private func orderStorageKey(householdId: UUID) -> String {
        let userComponent = currentMembership?.userId?.uuidString ?? "anonymous"
        return "family.profile.order.\(householdId.uuidString).\(userComponent)"
    }

    private func shouldCreateBirthdayAutomation(oldBirthDate: String?, newBirthDate: Date?) -> Bool {
        guard let newBirthDate else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let oldDate = oldBirthDate.flatMap { formatter.date(from: $0) }
        return oldDate != newBirthDate
    }

    private func createBirthdayTasksIfNeeded(profileName: String, draft: ManagedProfileDraft, householdId: UUID) async {
        guard
            let birthDate = draft.birthDate,
            let creatorId = currentMembershipId
        else { return }

        let now = Date()
        let templates: [(daysBefore: Int, title: String)] = [
            (30, "准备生日愿望清单"),
            (15, "预订餐厅与场地"),
            (7, "购买生日礼物"),
            (3, "确认蛋糕预订"),
            (1, "布置现场并取蛋糕"),
            (0, "陪伴成员，生日快乐！")
        ]

        for template in templates {
            let dueDate = birthdayReminderDate(baseBirthDate: birthDate, daysBefore: template.daysBefore, reference: now)
            let task = FamilyTask(
                id: UUID(),
                householdId: householdId,
                creatorId: creatorId,
                parentTaskId: nil,
                originalDueDate: dueDate,
                involvedMemberIds: nil,
                targetSubject: profileName,
                title: template.title,
                description: "生日自动任务（年度循环）",
                originalPrompt: nil,
                attachmentUrls: nil,
                externalContacts: nil,
                locationData: nil,
                externalSyncRefs: nil,
                alarmSetBy: nil,
                status: .new,
                priority: .normal,
                dueDate: dueDate,
                isAllDay: true,
                recurrenceRule: "FREQ=YEARLY",
                reminderOffsets: nil,
                estimatedCost: 0,
                createdAt: now,
                updatedAt: now
            )
            do {
                _ = try await taskService.createTask(task)
            } catch {
                #if DEBUG
                print("⚠️ [FamilyDebug] birthday automation task create failed - \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func birthdayReminderDate(baseBirthDate: Date, daysBefore: Int, reference: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let birthComponents = calendar.dateComponents([.month, .day], from: baseBirthDate)
        var targetComponents = calendar.dateComponents([.year], from: reference)
        targetComponents.month = birthComponents.month
        targetComponents.day = birthComponents.day
        let currentYearBirthday = calendar.date(from: targetComponents) ?? reference
        let candidateBirthday = currentYearBirthday < reference
            ? calendar.date(byAdding: .year, value: 1, to: currentYearBirthday) ?? currentYearBirthday
            : currentYearBirthday
        return calendar.date(byAdding: .day, value: -daysBefore, to: candidateBirthday) ?? candidateBirthday
    }

    private static let profileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func mapHouseholdRenameError(_ error: HouseholdRoutingError) -> String {
        switch error {
        case .invalidHouseholdName:
            return "家庭名称不能为空。"
        case .householdNameTaken:
            return "该家庭名称已被占用，请换一个名称。"
        case .unauthenticated:
            return "当前登录状态已失效，请重新登录后再试。"
        case .forbidden:
            return "只有创建者或管理员可以修改家庭名称。"
        case .householdNotFound:
            return "家庭不存在或已被删除，请刷新后重试。"
        case .backendMigrationRequired:
            return "后端尚未完成升级，请先执行最新 Supabase migration 后重试。"
        case .networkFailure:
            return "网络或服务异常，请稍后再试。"
        case .invalidInviteCode,
             .alreadyActiveMember,
             .joinRequestPending,
             .nonceExpired,
             .nonceConsumed,
             .unknown:
            return "修改家庭名称失败，请稍后重试。"
        }
    }
}
