import Foundation
import Combine
import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

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

    private struct FamilyMembersCachePayload: Codable {
        let profiles: [FamilyProfile]
        let members: [HouseholdMembership]
    }

    private static func membersCacheKey(for householdId: UUID) -> String {
        "family.members.snapshot.\(householdId.uuidString.lowercased())"
    }

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

        let cacheKey = Self.membersCacheKey(for: householdId)
        let cachedPayload: FamilyMembersCachePayload? = LocalCacheManager.shared.load(forKey: cacheKey)
        if let cachedPayload {
            profiles = cachedPayload.profiles
            members = cachedPayload.members
            applyLocalOrdering()
            errorMessage = nil
            hasLoadedOnce = true
        }

        let hadDiskCache = cachedPayload != nil
        let showBlockingSpinner = hadDiskCache == false
        if showBlockingSpinner {
            isLoading = true
        }
        errorMessage = nil
        defer {
            if showBlockingSpinner {
                isLoading = false
            }
            hasLoadedOnce = true
        }

        do {
            async let profileRows = profileService.fetchProfiles(in: householdId)
            async let membershipRows = membershipService.fetchMemberships(in: householdId)
            let (p, m) = try await (profileRows, membershipRows)
            profiles = p
            members = m
            applyLocalOrdering()
            let snapshot = FamilyMembersCachePayload(profiles: p, members: m)
            LocalCacheManager.shared.save(snapshot, forKey: cacheKey)
            #if DEBUG
            print("✅ [FamilyDebug] loadMembers success - profiles=\(p.count), memberships=\(m.count)")
            #endif
        } catch {
            if hadDiskCache == false {
                errorMessage = error.localizedDescription
            }
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
        let idsBeforeCreate = Set(profiles.map(\.id))
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
            await loadMembers()
            if let createdProfile = profiles.first(where: { idsBeforeCreate.contains($0.id) == false }) {
                await syncBirthdayTasks(for: createdProfile)
            }
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return error.localizedDescription
        }
    }

    func updateProfile(_ profile: FamilyProfile, draft: ManagedProfileDraft) async -> String? {
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
            await syncBirthdayTasks(for: updatedProfile)
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

    func syncBirthdayTasks(for profile: FamilyProfile) async {
        #if canImport(Supabase)
        struct ExistingBirthdayTaskRow: Decodable {
            let id: UUID
            let targetProfileIds: [UUID]?
            let taskType: String?
            let title: String?
            let targetSubject: String?
            let originalPrompt: String?

            enum CodingKeys: String, CodingKey {
                case id
                case targetProfileIds = "target_profile_ids"
                case taskType = "task_type"
                case title
                case targetSubject = "target_subject"
                case originalPrompt = "original_prompt"
            }
        }

        struct BirthdayTaskInsertFallbackPayload: Encodable {
            let householdId: UUID
            let creatorId: UUID
            let title: String
            let dueDate: Date
            let recurrenceRule: String
            let taskType: String
            let targetProfileIds: [UUID]
            let targetSubject: String
            let description: String
            let originalPrompt: String

            enum CodingKeys: String, CodingKey {
                case householdId = "household_id"
                case creatorId = "creator_id"
                case title
                case dueDate = "due_date"
                case recurrenceRule = "recurrence_rule"
                case taskType = "task_type"
                case targetProfileIds = "target_profile_ids"
                case targetSubject = "target_subject"
                case description
                case originalPrompt = "original_prompt"
            }
        }

        let client = SupabaseManager.shared.client
        do {
            var deletedCount = 0
            var insertedCount = 0
            #if DEBUG
            print("🎂 [BirthdaySync] start - profileId=\(profile.id.uuidString), householdId=\(profile.householdId.uuidString), name=\(profile.name), birthDate=\(profile.birthDate ?? "nil")")
            #endif

            // Step 1: 强制清理（Clear First）- 先查 ID，再逐条删，保证 deleted 统计准确
            let rows: [ExistingBirthdayTaskRow] = try await client
                .from("tasks")
                .select("id,target_profile_ids,task_type,title,target_subject,original_prompt")
                .eq("household_id", value: profile.householdId.uuidString)
                .execute()
                .value
            #if DEBUG
            let hasTargetIdsCount = rows.filter { ($0.targetProfileIds?.isEmpty == false) }.count
            let containsProfileCount = rows.filter { $0.targetProfileIds?.contains(profile.id) == true }.count
            let taskTypeDistribution = Dictionary(grouping: rows, by: { $0.taskType ?? "nil" })
                .map { (key: String, value: [ExistingBirthdayTaskRow]) in
                    "\(key)=\(value.count)"
                }
                .sorted()
                .joined(separator: ", ")
            let sample = rows.prefix(12).map { row in
                let ids = row.targetProfileIds?.map(\.uuidString).joined(separator: ",") ?? "nil"
                return "id=\(row.id.uuidString), task_type=\(row.taskType ?? "nil"), target_profile_ids=\(ids)"
            }.joined(separator: "\n")
            print(
                """
                🎂 [BirthdaySync] clear debug - fetchedRows=\(rows.count)
                🎂 [BirthdaySync] clear debug - hasTargetIds=\(hasTargetIdsCount), containsProfileId=\(containsProfileCount)
                🎂 [BirthdaySync] clear debug - taskTypeDistribution=\(taskTypeDistribution)
                🎂 [BirthdaySync] clear debug - profileId=\(profile.id.uuidString), householdId=\(profile.householdId.uuidString)
                🎂 [BirthdaySync] clear debug - sampleRows(<=12):
                \(sample)
                """
            )
            #endif
            let tasksToDelete = rows.filter { row in
                row.targetProfileIds?.contains(profile.id) == true
            }
            let syncMarker = birthdaySyncMarker(for: profile.id)
            let legacyTasksToDelete = rows.filter { row in
                let hasNoStructuredTag = (row.taskType?.isEmpty ?? true) || row.taskType == nil
                guard hasNoStructuredTag else { return false }
                let title = row.title ?? ""
                let hitMarker = row.originalPrompt == syncMarker
                let hitSubjectAndBirthday = (row.targetSubject == profile.name) && title.contains("生日")
                let hitLegacyTitleOnly = title.contains("生日") && title.contains(profile.name)
                return hitMarker || hitSubjectAndBirthday || hitLegacyTitleOnly
            }
            let deleteRows = Array(Dictionary(uniqueKeysWithValues: (tasksToDelete + legacyTasksToDelete).map { ($0.id, $0) }).values)
            #if DEBUG
            print("🎂 [BirthdaySync] clear path=structured+legacy, structuredFound=\(tasksToDelete.count), legacyFound=\(legacyTasksToDelete.count), merged=\(deleteRows.count), rawRows=\(rows.count)")
            #endif

            if deleteRows.isEmpty == false {
                for row in deleteRows {
                    do {
                        _ = try await client
                            .from("tasks")
                            .delete()
                            .eq("id", value: row.id.uuidString)
                            .execute()
                        deletedCount += 1
                    } catch {
                        #if DEBUG
                        let nsError = error as NSError
                        let ui = nsError.userInfo
                        let code = (ui["code"] as? String)
                            ?? (ui["SQLSTATE"] as? String)
                            ?? "\(nsError.code)"
                        let details = ui["details"] as? String
                        let hint = ui["hint"] as? String
                        print(
                            """
                            ⚠️ [BirthdaySync] delete failed - taskId=\(row.id.uuidString)
                            localizedDescription=\(error.localizedDescription)
                            domain=\(nsError.domain)
                            code=\(code)
                            details=\(details ?? "nil")
                            hint=\(hint ?? "nil")
                            userInfoKeys=\(Array(ui.keys).map { "\($0)" }.joined(separator: ","))
                            """
                        )
                        #endif
                    }
                }
            }

            // Step 2: 若生日为空，清理后直接结束
            let birthDateText = profile.birthDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if birthDateText.isEmpty {
                #if DEBUG
                print("🎂 [BirthdaySync] branch=clear-only (birthDate empty)")
                print("🎂 [BirthdaySync] summary - deleted=\(deletedCount), inserted=\(insertedCount)")
                #endif
                return
            }

            // Step 3: 计算下一次生日
            guard let birthDate = Self.profileDateFormatter.date(from: birthDateText) else {
                #if DEBUG
                print("🎂 [BirthdaySync] stop - invalid birthDate format: \(birthDateText)")
                #endif
                return
            }
            guard let nextBirthday = nextBirthdayDate(from: birthDate, reference: Date()) else {
                #if DEBUG
                print("🎂 [BirthdaySync] stop - nextBirthday calculate failed")
                #endif
                return
            }
            #if DEBUG
            print("🎂 [BirthdaySync] nextBirthday=\(nextBirthday)")
            #endif

            guard let creatorId = currentMembershipId else { return }
            #if DEBUG
            print("🎂 [BirthdaySync] recreate start - creatorMembershipId=\(creatorId.uuidString)")
            #endif
            let templates: [(offset: Int, title: String)] = [
                (-30, "准备 \(profile.name) 的生日愿望清单"),
                (-15, "为 \(profile.name) 预订生日餐厅/场地"),
                (-7, "购买 \(profile.name) 的生日礼物"),
                (-3, "确认 \(profile.name) 的生日蛋糕预订"),
                (-1, "布置现场并取回 \(profile.name) 的生日蛋糕"),
                (0, "陪伴 \(profile.name)，祝生日快乐！")
            ]

            let fallbackPayloads = templates.compactMap { template -> BirthdayTaskInsertFallbackPayload? in
                guard let dueDate = Calendar.current.date(byAdding: .day, value: template.offset, to: nextBirthday) else {
                    return nil
                }
                return BirthdayTaskInsertFallbackPayload(
                    householdId: profile.householdId,
                    creatorId: creatorId,
                    title: template.title,
                    dueDate: dueDate,
                    recurrenceRule: "yearly",
                    taskType: "birthday_reminder",
                    targetProfileIds: [profile.id],
                    targetSubject: profile.name,
                    description: "生日自动任务（年度循环）",
                    originalPrompt: birthdaySyncMarker(for: profile.id)
                )
            }

            if fallbackPayloads.isEmpty == false {
                _ = try await client
                    .from("tasks")
                    .insert(fallbackPayloads)
                    .execute()
                insertedCount += fallbackPayloads.count
                #if DEBUG
                print("🎂 [BirthdaySync] insert path=target_profile_ids, inserted=\(fallbackPayloads.count)")
                #endif
            }
            #if DEBUG
            print("🎂 [BirthdaySync] done - profileId=\(profile.id.uuidString)")
            print("🎂 [BirthdaySync] summary - deleted=\(deletedCount), inserted=\(insertedCount)")
            #endif
        } catch {
            #if DEBUG
            let nsError = error as NSError
            let userInfo = nsError.userInfo
            let code = (userInfo["code"] as? String)
                ?? (userInfo["SQLSTATE"] as? String)
                ?? "\(nsError.code)"
            let details = userInfo["details"] as? String
            let hint = userInfo["hint"] as? String
            print(
                """
                ⚠️ [FamilyDebug] syncBirthdayTasks failed
                localizedDescription=\(error.localizedDescription)
                domain=\(nsError.domain)
                code=\(code)
                details=\(details ?? "nil")
                hint=\(hint ?? "nil")
                userInfoKeys=\(Array(userInfo.keys).map { "\($0)" }.joined(separator: ","))
                """
            )
            #endif
        }
        #else
        _ = profile
        #endif
    }

    private func nextBirthdayDate(from birthDate: Date, reference: Date) -> Date? {
        let calendar = Calendar.current
        let birthComponents = calendar.dateComponents([.month, .day], from: birthDate)
        var targetComponents = calendar.dateComponents([.year], from: reference)
        targetComponents.month = birthComponents.month
        targetComponents.day = birthComponents.day
        guard let thisYearBirthday = calendar.date(from: targetComponents) else { return nil }
        if thisYearBirthday < calendar.startOfDay(for: reference) {
            return calendar.date(byAdding: .year, value: 1, to: thisYearBirthday)
        }
        return thisYearBirthday
    }

    private static let profileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func birthdaySyncMarker(for profileId: UUID) -> String {
        "birthday_sync_profile:\(profileId.uuidString.lowercased())"
    }

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
