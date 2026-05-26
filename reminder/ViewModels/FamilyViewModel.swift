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
    @Published var isDisbanding = false
    @Published var showDisbandErrorAlert = false
    @Published var disbandError: String?
    @Published var showLeaveConfirmation = false
    @Published var showCreatorBlockAlert = false
    @Published var isLeaving = false
    @Published var leaveErrorMessage: String?
    @Published var transferSuccessToastMessage: String?

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

        func filteredToActiveMembers(in householdId: UUID) -> FamilyMembersCachePayload {
            let roster = HouseholdMemberRoster(profiles: profiles, memberships: members)
                .filteredToActiveMembers(in: householdId)
            return FamilyMembersCachePayload(profiles: roster.profiles, members: roster.memberships)
        }
    }

    private static func membersCacheKey(for householdId: UUID) -> String {
        "family.members.snapshot.\(householdId.uuidString.lowercased())"
    }

    static func tasksCacheKey(for householdId: UUID) -> String {
        "schedule.tasks.snapshot.\(householdId.uuidString.lowercased())"
    }

    var canDisbandCurrentHousehold: Bool {
        currentMembership?.hasRole(.creator) == true
    }

    var canLeaveCurrentHousehold: Bool {
        canDisbandCurrentHousehold == false
    }

    var canTransferOwnership: Bool {
        canDisbandCurrentHousehold
    }

    var currentAuthUserId: UUID? {
        currentMembership?.userId ?? currentUserProfile?.userId
    }

    var transferHouseholdId: UUID? {
        currentHouseholdId
    }

    var transferMembersSnapshot: [HouseholdMembership] {
        members
    }

    var transferProfilesSnapshot: [FamilyProfile] {
        profiles
    }

    func showTransferSuccessToast() {
        transferSuccessToastMessage = "权限已成功转移"
    }

    func acknowledgeTransferSuccessToast() {
        transferSuccessToastMessage = nil
    }

    func applyLocalRoleDowngradeAfterOwnershipTransfer() async {
        guard let membershipId = currentMembershipId,
              let index = members.firstIndex(where: { $0.id == membershipId }) else {
            await loadMembers()
            return
        }

        var downgraded = members[index]
        downgraded.role = MembershipRole.member.rawValue
        members[index] = downgraded
        attachMembershipsFromFlatMembers()
        applyLocalOrdering()
        postScheduleHouseholdRosterChangedIfNeeded()
        await loadMembers()
    }

    /// 解散当前家庭：调用 RPC、清洗本地缓存；成功返回 `true` 供 View 切换根路由。
    @discardableResult
    func confirmDisband(
        householdId: UUID,
        currentName: String,
        userInputName: String
    ) async -> Bool {
        isDisbanding = true
        disbandError = nil
        showDisbandErrorAlert = false
        defer { isDisbanding = false }

        let normalizedCurrent = currentName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedInput = userInputName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedInput.isEmpty == false, normalizedInput == normalizedCurrent else {
            #if DEBUG
            print("🔎 [DisbandDebug] ViewModel 本地名称校验未通过。")
            print("   ↳ 当前记录的真实家庭名称: '\(currentName)'")
            print("   ↳ 用户输入的匹配名称: '\(userInputName)'")
            print("   ↳ 归一化后 current='\(normalizedCurrent)' input='\(normalizedInput)'")
            print("   ↳ ID: \(householdId.uuidString)")
            #endif
            disbandError = "群组名称输入错误，与当前群组的真实名称不匹配，请重新核对。"
            showDisbandErrorAlert = true
            return false
        }

        let trimmedInputForRPC = userInputName.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        print("🔎 [DisbandDebug] ViewModel 准备解散。")
        print("   ↳ 当前记录的真实家庭名称: '\(currentName)'")
        print("   ↳ 用户输入的匹配名称: '\(userInputName)'")
        print("   ↳ 传入 RPC 的 expectedName: '\(trimmedInputForRPC)'")
        print("   ↳ ID: \(householdId.uuidString)")
        #endif

        do {
            await householdRoutingService.cleanUpHouseholdFeedbackAudios(householdId: householdId)
            try await householdRoutingService.disbandHousehold(
                id: householdId,
                expectedName: trimmedInputForRPC
            )
            purgeLocalHouseholdData(for: householdId)
            currentHouseholdId = nil
            currentMembershipId = nil
            #if DEBUG
            print("✅ [DisbandDebug] 解散成功")
            #endif
            return true
        } catch {
            #if DEBUG
            print("❌ [DisbandDebug] 解散失败，底层错误: \(error)")
            print("❌ [DisbandDebug] ViewModel 捕获 Service 异常: \(error.localizedDescription)")
            dump(error)
            #endif
            disbandError = mapDisbandErrorMessage(error)
            showDisbandErrorAlert = true
            return false
        }
    }

    func requestToLeave() {
        leaveErrorMessage = nil
        if currentMembership?.hasRole(.creator) == true {
            showCreatorBlockAlert = true
        } else {
            showLeaveConfirmation = true
        }
    }

    func acknowledgeLeaveError() {
        leaveErrorMessage = nil
    }

    /// 退出当前群组：调用 RPC、清洗本地缓存并完成跌落路由。
    @discardableResult
    func confirmLeave(householdId: UUID, appRouter: AppRouter) async -> Bool {
        isLeaving = true
        leaveErrorMessage = nil
        defer { isLeaving = false }

        do {
            try await householdRoutingService.leaveHousehold(householdId: householdId)
            purgeLocalHouseholdData(for: householdId)
            currentHouseholdId = nil
            currentMembershipId = nil
            showLeaveConfirmation = false
            await appRouter.routeAfterLeavingHousehold(householdId)
            return true
        } catch {
            #if DEBUG
            print("❌ [LeaveDebug] 退出群组失败: \(error)")
            #endif
            leaveErrorMessage = mapLeaveErrorMessage(error)
            if shouldBlockCreatorLeave(for: error) {
                showCreatorBlockAlert = true
                showLeaveConfirmation = false
            }
            return false
        }
    }

    private func shouldBlockCreatorLeave(for error: Error) -> Bool {
        if let routingError = error as? HouseholdRoutingError, case .creatorCannotLeave = routingError {
            return true
        }
        return error.localizedDescription.lowercased().contains("creator_cannot_leave")
    }

    private enum LeaveCopy {
        static let creatorCannotLeave = String(localized: "You are the creator of this group. Transfer ownership or disband the group before leaving.")
        static let sessionExpired = String(localized: "Your sign-in session has expired. Please sign in again.")
        static let householdNotFound = String(localized: "This group does not exist or has been deleted.")
        static let backendMigrationRequired = String(localized: "Backend upgrade required. Please apply the latest Supabase migration and try again.")
        static let forbidden = String(localized: "You don't have permission to perform this action.")
        static let leaveFailed = String(localized: "Could not leave the group. Please try again later.")
    }

    private func mapLeaveErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("creator_cannot_leave") {
            return LeaveCopy.creatorCannotLeave
        }
        if message.contains("unauthenticated") || message.contains("jwt") || message.contains("session") {
            return LeaveCopy.sessionExpired
        }
        if let routingError = error as? HouseholdRoutingError {
            switch routingError {
            case .creatorCannotLeave:
                return LeaveCopy.creatorCannotLeave
            case .unauthenticated:
                return LeaveCopy.sessionExpired
            case .householdNotFound:
                return LeaveCopy.householdNotFound
            case .backendMigrationRequired:
                return LeaveCopy.backendMigrationRequired
            case .forbidden:
                return LeaveCopy.forbidden
            default:
                break
            }
        }
        return LeaveCopy.leaveFailed
    }

    func purgeLocalHouseholdData(for householdId: UUID) {
        profiles = []
        orderedProfiles = []
        members = []
        errorMessage = nil
        hasLoadedOnce = false
        LocalCacheManager.shared.remove(forKey: Self.membersCacheKey(for: householdId))
        LocalCacheManager.shared.remove(forKey: Self.tasksCacheKey(for: householdId))
        NotificationCenter.default.post(name: .householdDidDisband, object: householdId)
    }

    private func mapDisbandErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("household_name_mismatch") {
            return "群组名称输入错误，与当前群组的真实名称不匹配，请重新核对。"
        }
        if message.contains("unauthorized_not_creator")
            || message.contains("unauthorized")
            || message.contains("forbidden") {
            return "权限不足。只有当前群组的创建者才有权解散该群组。"
        }
        if message.contains("unauthenticated") || message.contains("jwt") || message.contains("session") {
            return "登录状态已失效，请重新登录后再试。"
        }
        if let routingError = error as? HouseholdRoutingError {
            switch routingError {
            case .householdNameMismatch:
                return "群组名称输入错误，与当前群组的真实名称不匹配，请重新核对。"
            case .disbandUnauthorized, .forbidden:
                return "权限不足。只有当前群组的创建者才有权解散该群组。"
            case .unauthenticated:
                return "登录状态已失效，请重新登录后再试。"
            case .householdNotFound:
                return "群组不存在或已被解散。"
            case .backendMigrationRequired:
                return "后端尚未完成升级，请先执行最新 Supabase migration 后重试。"
            default:
                break
            }
        }
        return "网络连接异常或服务器响应失败，请稍后重试。"
    }

    private func postScheduleHouseholdRosterChangedIfNeeded() {
        guard let householdId = currentHouseholdId else { return }
        NotificationCenter.default.post(
            name: .scheduleHouseholdRosterDidChange,
            object: householdId
        )
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
            errorMessage = "当前未选择群组。"
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
            let filtered = cachedPayload.filteredToActiveMembers(in: householdId)
            profiles = filtered.profiles
            let fromEmbed = FamilyProfile.uniqueMembershipsFlattened(from: profiles)
            members = fromEmbed.isEmpty ? filtered.members : fromEmbed
            attachMembershipsFromFlatMembers()
            sortProfilesForDisplay()
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
            let roster = try await membershipService.fetchMemberRoster(in: householdId, activeOnly: true)
                .filteredToActiveMembers(in: householdId)
            let rawMemberships = roster.memberships
            var p = roster.profiles
            #if DEBUG
            Self.debugLogFetchedProfiles(p, label: "fetchMemberRoster 原始响应")
            Self.debugLogFetchedMemberships(rawMemberships, label: "fetchMemberRoster memberships")
            #endif
            p = FamilyProfile.mergingMembershipRows(p, memberships: rawMemberships)
            #if DEBUG
            Self.debugLogFetchedProfiles(p, label: "mergingMembershipRows 之后（即将写入 profiles）")
            #endif
            profiles = p
            sortProfilesForDisplay()
            let embedded = FamilyProfile.uniqueMembershipsFlattened(from: p)
            var seen = Set<UUID>()
            var combined: [HouseholdMembership] = []
            for row in embedded + rawMemberships where seen.insert(row.id).inserted {
                combined.append(row)
            }
            combined.sort { lhs, rhs in
                let lr = membershipRoleSortIndex(for: lhs)
                let rr = membershipRoleSortIndex(for: rhs)
                if lr != rr {
                    return lr < rr
                }
                return lhs.createdAt < rhs.createdAt
            }
            members = combined
            attachMembershipsFromFlatMembers()
            applyLocalOrdering()
            let snapshot = FamilyMembersCachePayload(profiles: profiles, members: members)
            LocalCacheManager.shared.save(snapshot, forKey: cacheKey)
            #if DEBUG
            print("✅ [FamilyDebug] loadMembers success - profiles=\(p.count), memberships=\(members.count)")
            #endif
        } catch {
            if hadDiskCache == false {
                errorMessage = error.localizedDescription
            }
            print("❌ [FetchMembers] loadMembers 失败: \(error)")
            if let decodingError = error as? DecodingError {
                print("🔍 详细解析错误: \(decodingError)")
            }
            #if DEBUG
            print("   phase: membershipService.fetchMemberRoster")
            print("   household_id=\(householdId.uuidString)")
            #endif
        }
    }

    /// 将扁平 `members` 合并回档案，保证 `displayName` 能读到 `household_memberships.nickname`。
    private func attachMembershipsFromFlatMembers() {
        profiles = FamilyProfile.mergingMembershipRows(profiles, memberships: members)
        if orderedProfiles.isEmpty == false {
            orderedProfiles = FamilyProfile.mergingMembershipRows(orderedProfiles, memberships: members)
        }
    }

    /// 当 `fetchProfiles` 返回 `[]` 时，按 `profile_id` 逐条 hydrate，并 **必须** 挂载扁平 membership。
    private func hydrateMissingProfilesFromMemberships(
        memberships: [HouseholdMembership],
        into profiles: inout [FamilyProfile]
    ) async {
        let profileIds = Set(memberships.compactMap(\.profileId))
        guard profileIds.isEmpty == false else { return }

        for profileId in profileIds {
            guard profiles.contains(where: { $0.id == profileId }) == false else { continue }
            let related = memberships.filter { $0.profileId == profileId }
            guard related.isEmpty == false else { continue }

            do {
                if let fetched = try await profileService.fetchProfile(id: profileId) {
                    let merged = fetched.attachingMemberships(from: memberships, explicitFallback: related)
                    profiles.append(merged)
                    #if DEBUG
                    print("✅ [FamilyDebug] hydrateMissingProfile — profile_id=\(profileId.uuidString) memberships=\(merged.householdMemberships?.count ?? 0)")
                    #endif
                    continue
                }
            } catch {
                #if DEBUG
                print("❌ [FamilyDebug] hydrateMissingProfile fetch failed — profile_id=\(profileId.uuidString) error=\(error.localizedDescription)")
                #endif
            }

            if let anchor = related.first {
                let synthetic = FamilyProfile.syntheticPlaceholder(
                    from: anchor,
                    profileId: profileId,
                    relatedMemberships: related
                )
                profiles.append(synthetic)
                #if DEBUG
                print("✅ [FamilyDebug] hydrateMissingProfile synthetic — profile_id=\(profileId.uuidString) memberships=\(related.count)")
                #endif
            }
        }
    }

    /// 创建者行必须展示 `family_profiles` 完整档案：按 creator membership 的 `profile_id` 再拉一次单行并合并身份。
    private func hydrateCreatorProfileIfNeeded(
        memberships: [HouseholdMembership],
        into profiles: inout [FamilyProfile]
    ) async {
        guard let creatorMembership = memberships.first(where: { $0.hasRole(.creator) && $0.isActiveMembership() }) else {
            return
        }
        let profileId = creatorMembership.profileId
            ?? profiles.first(where: { $0.userId == creatorMembership.userId })?.id
        guard let profileId else { return }

        let relatedToCreator = memberships.filter {
            $0.profileId == profileId
                || ($0.userId != nil && $0.userId == creatorMembership.userId && $0.householdId == creatorMembership.householdId)
        }
        let creatorFallback = relatedToCreator.isEmpty ? [creatorMembership] : relatedToCreator

        do {
            if let fetched = try await profileService.fetchProfile(id: profileId) {
                let merged = fetched.attachingMemberships(from: memberships, explicitFallback: creatorFallback)
                upsertProfile(merged, profileId: profileId, into: &profiles)
                #if DEBUG
                print("✅ [FamilyDebug] hydrateCreatorProfile — profile_id=\(profileId.uuidString) name=\"\(merged.name)\" memberships=\(merged.householdMemberships?.count ?? 0)")
                #endif
                return
            }
        } catch {
            #if DEBUG
            print("❌ [FamilyDebug] hydrateCreatorProfile fetch failed — profile_id=\(profileId.uuidString) error=\(error.localizedDescription)")
            #endif
        }

        let synthetic = FamilyProfile.syntheticPlaceholder(
            from: creatorMembership,
            profileId: profileId,
            relatedMemberships: creatorFallback
        )
        upsertProfile(synthetic, profileId: profileId, into: &profiles)
        #if DEBUG
        print("✅ [FamilyDebug] hydrateCreatorProfile synthetic — profile_id=\(profileId.uuidString) memberships=\(creatorFallback.count)")
        #endif
    }

    private func upsertProfile(_ profile: FamilyProfile, profileId: UUID, into profiles: inout [FamilyProfile]) {
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    func didLoginSuccessfully() async {
        requiresLogin = false
        await loadMembers()
    }

    @discardableResult
    func createMember(_ member: HouseholdMembership) async -> HouseholdMembership? {
        guard let householdId = currentHouseholdId else {
            errorMessage = "当前未选择群组。"
            return nil
        }
        guard member.householdId == householdId else {
            errorMessage = "成员创建失败：群组上下文不一致。"
            return nil
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let createdMember = try await membershipService.createMembership(member)
            await loadMembers()
            postScheduleHouseholdRosterChangedIfNeeded()
            return createdMember
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createLocalProfile(householdId: UUID, draft: LocalProfileDraft) async -> String? {
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
            try await profileService.createLocalProfile(
                householdId: householdId,
                draft: normalizedDraft
            )
            await loadMembers()
            if let createdProfile = profiles.first(where: { idsBeforeCreate.contains($0.id) == false }) {
                await syncBirthdayTasks(for: createdProfile)
            }
            postScheduleHouseholdRosterChangedIfNeeded()
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return error.localizedDescription
        }
    }

    func updateProfile(_ profile: FamilyProfile, draft: LocalProfileDraft) async -> String? {
        let trimmedDisplayName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDisplayName.isEmpty == false else {
            return "称呼不能为空。"
        }

        guard canEditProfile(profile) else {
            return "当前没有权限修改该成员资料。"
        }

        let targetProfileId = profile.id
        guard let householdId = currentHouseholdId ?? profile.householdId else {
            return "当前未选择群组。"
        }

        var profileDraft = draft
        profileDraft.name = trimmedDisplayName

        do {
            do {
                try await membershipService.updateNickname(
                    householdId: householdId,
                    profileId: targetProfileId,
                    nickname: trimmedDisplayName
                )
            } catch {
                #if DEBUG
                print("⚠️ [FamilyDebug] 更新 membership 昵称时出错（虚拟成员可忽略）: \(error.localizedDescription)")
                #endif
            }

            try await profileService.updateProfile(profileId: targetProfileId, draft: profileDraft)

            var updatedProfile = profile
            updatedProfile.name = trimmedDisplayName
            if let memberIndex = members.firstIndex(where: {
                $0.householdId == householdId && $0.profileId == targetProfileId
            }) {
                members[memberIndex].nickname = trimmedDisplayName
                var memberships = updatedProfile.memberships ?? []
                if let embeddedIndex = memberships.firstIndex(where: { $0.id == members[memberIndex].id }) {
                    memberships[embeddedIndex].nickname = trimmedDisplayName
                    updatedProfile.memberships = memberships
                } else {
                    updatedProfile.memberships = [members[memberIndex]]
                }
            }
            updatedProfile.avatarUrl = profileDraft.avatarURL
            updatedProfile.gender = profileDraft.gender
            updatedProfile.birthDate = profileDraft.birthDate.map { Self.profileDateFormatter.string(from: $0) }
            updatedProfile.idCardNum = profileDraft.idCardNum
            updatedProfile.passportNum = profileDraft.passportNum
            updatedProfile.permitNum = profileDraft.permitNum
            updatedProfile.height = profileDraft.height
            updatedProfile.weight = profileDraft.weight
            updatedProfile.school = profileDraft.school
            updatedProfile.grade = profileDraft.grade
            updatedProfile.email = profileDraft.email
            updatedProfile.mainPhone = profileDraft.mainPhone
            updatedProfile.secondPhone = profileDraft.secondPhone

            if let index = profiles.firstIndex(where: { $0.id == updatedProfile.id }) {
                profiles[index] = updatedProfile
            } else {
                profiles.append(updatedProfile)
            }
            applyLocalOrdering()
            attachMembershipsFromFlatMembers()
            applyLocalOrdering()
            await syncBirthdayTasks(for: updatedProfile)
            await loadMembers()
            errorMessage = nil
            postScheduleHouseholdRosterChangedIfNeeded()
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

    /// 删除托管成员档案前清理 Storage 头像；失败不阻断后续数据库操作。
    func cleanUpStoredAvatar(for profileId: UUID) async {
        await authService.cleanUpProfileAvatar(profileId: profileId)
    }

    func canEditProfile(_ profile: FamilyProfile?) -> Bool {
        guard let profile else { return canCurrentUserManageHousehold }
        guard let cm = currentMembership else { return false }
        if let uid = profile.userId, let cmUserId = cm.userId, uid == cmUserId { return true }
        if membership(for: profile)?.id == cm.id { return true }
        if canCurrentUserManageHousehold, profile.userId == nil { return true }
        return false
    }

    var currentUserProfile: FamilyProfile? {
        guard let cm = currentMembership else { return nil }
        if let uid = cm.userId,
           let byUserId = profiles.first(where: { $0.userId == uid }) {
            return byUserId
        }
        return profiles.first { membership(for: $0)?.id == cm.id }
    }

    /// 与档案对应的 **`household_memberships`**：优先嵌套 `memberships`；否则回退到扁平 `members`（兼容旧缓存 / 未带嵌套的响应）。
    /// - Note: 回退时先匹配 **`active`**，再匹配同档案下其它状态（如 **`pending`** 邀请行），避免列表角色与点按分流异常。
    func membership(for profile: FamilyProfile) -> HouseholdMembership? {
        if let embedded = profile.primaryMembership {
            return embedded
        }
        let scopedMembers: [HouseholdMembership]
        if let householdId = currentHouseholdId {
            scopedMembers = members.filter { $0.householdId == householdId }
        } else if let profileHouseholdId = profile.householdId {
            scopedMembers = members.filter { $0.householdId == profileHouseholdId }
        } else {
            scopedMembers = members
        }
        if let activeByProfile = scopedMembers.first(where: { $0.profileId == profile.id && $0.isActiveMembership() }) {
            return activeByProfile
        }
        if let anyByProfile = scopedMembers.first(where: { $0.profileId == profile.id }) {
            return anyByProfile
        }
        if let uid = profile.userId {
            if let activeByUser = scopedMembers.first(where: { $0.userId == uid && $0.isActiveMembership() }) {
                return activeByUser
            }
            return scopedMembers.first(where: { $0.userId == uid })
        }
        return nil
    }

    /// 列表/排序用的角色：嵌套优先，否则扁平 `members`（与 `FamilyView.resolvedMembership` 一致）。
    private func resolvedListRole(_ profile: FamilyProfile) -> MembershipRole? {
        profile.currentMembershipRole ?? membership(for: profile)?.parsedRole
    }

    var otherProfiles: [FamilyProfile] {
        guard let me = currentUserProfile else { return orderedProfiles }
        return orderedProfiles.filter { $0.id != me.id }
    }

    /// 非「创建者」身份行在列表中的顺序（与家庭页「家庭成员」区块一致）。
    var nonCreatorProfiles: [FamilyProfile] {
        orderedProfiles.filter { resolvedListRole($0) != .creator }
    }

    func moveOtherProfiles(fromOffsets source: IndexSet, toOffset destination: Int) {
        var others = otherProfiles
        others.move(fromOffsets: source, toOffset: destination)
        let me = currentUserProfile
        orderedProfiles = (me.map { [$0] } ?? []) + others
        persistOrder(for: others)
    }

    /// 在「创建者单独展示」布局下，对除创建者外的成员拖动排序并持久化顺序。
    func moveNonCreatorProfiles(fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = nonCreatorProfiles
        list.move(fromOffsets: source, toOffset: destination)
        let creatorBlock = orderedProfiles.filter { resolvedListRole($0) == .creator }.prefix(1).map { $0 }
        orderedProfiles = creatorBlock + list
        let me = currentUserProfile
        let persistOthers = orderedProfiles.filter { $0.id != me?.id }
        persistOrder(for: persistOthers)
    }

    /// 影子成员的邀请链接以 `membership.id` 作为 token。
    func generateSignedInviteLink(for member: HouseholdMembership) async -> URL? {
        let token = "invite-\(member.id.uuidString.lowercased())"
        do {
            return try await inviteLinkService.generateSignedInviteLink(
                token: token,
                contactMethod: .appPush,
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
            _ = try await membershipService.updateMembership(member)
            await loadMembers()
            postScheduleHouseholdRosterChangedIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameHousehold(householdId: UUID, newName: String) async -> String? {
        let stableName = String(newName)
        let normalizedName = stableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            return "群组名称不能为空。"
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
        switch currentMembership?.parsedRole {
        case .creator, .admin:
            return true
        case .member, .none:
            return false
        }
    }

    private func applyLocalOrdering() {
        guard let householdId = currentHouseholdId else {
            orderedProfiles = profiles
            pinCreatorFirstIfPresent()
            return
        }
        let me = currentUserProfile
        let savedOrder = loadPersistedOrder(householdId: householdId)
        let orderMap = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($1, $0) })
        let meId = me?.id

        func profileListSortRank(_ profile: FamilyProfile) -> Int {
            guard let role = profile.primaryMembership?.parsedRole else {
                return 3
            }
            return membershipRoleSortIndex(role)
        }

        let others = profiles
            .filter { $0.id != meId }
            .sorted { lhs, rhs in
                let leftRank = profileListSortRank(lhs)
                let rightRank = profileListSortRank(rhs)
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                let leftOrder = orderMap[lhs.id] ?? Int.max
                let rightOrder = orderMap[rhs.id] ?? Int.max
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }

        orderedProfiles = (me.map { [$0] } ?? []) + others
        pinCreatorFirstIfPresent()
    }

    /// 家庭页设计：创建者卡片置顶；其余行保持相对顺序不变。
    private func pinCreatorFirstIfPresent() {
        guard let idx = orderedProfiles.firstIndex(where: { resolvedListRole($0) == .creator }) else { return }
        let creator = orderedProfiles[idx]
        var tail = orderedProfiles
        tail.remove(at: idx)
        orderedProfiles = [creator] + tail
    }

    /// 强制排序：创建者 → 管理员 → 成员 → **无 membership 的档案**；同梯队内按加入时间、再按名称。
    private func sortProfilesForDisplay() {
        profiles.sort { lhs, rhs in
            let lr = profileAggregatedRoleRank(lhs)
            let rr = profileAggregatedRoleRank(rhs)
            if lr != rr {
                return lr < rr
            }
            let lJoined = lhs.primaryMembership?.joinedAt ?? lhs.primaryMembership?.createdAt
            let rJoined = rhs.primaryMembership?.joinedAt ?? rhs.primaryMembership?.createdAt
            if let lJoined, let rJoined, lJoined != rJoined {
                return lJoined < rJoined
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func profileAggregatedRoleRank(_ profile: FamilyProfile) -> Int {
        guard let role = profile.primaryMembership?.parsedRole else {
            return 3
        }
        return membershipRoleSortIndex(role)
    }

    private func membershipRoleSortIndex(for membership: HouseholdMembership) -> Int {
        membershipRoleSortIndex(membership.parsedRole ?? .member)
    }

    private func membershipRoleSortIndex(_ role: MembershipRole) -> Int {
        switch role {
        case .creator:
            return 0
        case .admin:
            return 1
        case .member:
            return 2
        }
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
        guard let householdId = currentHouseholdId ?? profile.householdId else { return }

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
            let recurrenceEndDate: Date?
            let recurrenceInterval: Int?
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
                case recurrenceEndDate = "recurrence_end_date"
                case recurrenceInterval = "recurrence_interval"
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
            print("🎂 [BirthdaySync] start - profileId=\(profile.id.uuidString), householdId=\(householdId.uuidString), name=\(profile.name), birthDate=\(profile.birthDate ?? "nil")")
            #endif

            // Step 1: 强制清理（Clear First）- 先查 ID，再逐条删，保证 deleted 统计准确
            let rows: [ExistingBirthdayTaskRow] = try await client
                .from("tasks")
                .select("id,target_profile_ids,task_type,title,target_subject,original_prompt")
                .eq("household_id", value: householdId.uuidString)
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
                🎂 [BirthdaySync] clear debug - profileId=\(profile.id.uuidString), householdId=\(householdId.uuidString)
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
                    householdId: householdId,
                    creatorId: creatorId,
                    title: template.title,
                    dueDate: dueDate,
                    recurrenceRule: "yearly",
                    recurrenceEndDate: nil,
                    recurrenceInterval: 1,
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
            return "群组名称不能为空。"
        case .householdNameTaken:
            return "该群组名称已被占用，请换一个名称。"
        case .unauthenticated:
            return "当前登录状态已失效，请重新登录后再试。"
        case .forbidden:
            return "只有创建者或管理员可以修改群组名称。"
        case .householdNotFound:
            return "群组不存在或已被删除，请刷新后重试。"
        case .backendMigrationRequired:
            return "后端尚未完成升级，请先执行最新 Supabase migration 后重试。"
        case .networkFailure:
            return "网络或服务异常，请稍后再试。"
        case .invalidInviteCode,
             .alreadyActiveMember,
             .joinRequestPending,
             .nonceExpired,
             .nonceConsumed,
             .householdNameMismatch,
             .disbandUnauthorized,
             .creatorCannotLeave,
             .transferUnauthorized,
             .transferInvalidTarget,
             .unknown:
            return "修改群组名称失败，请稍后重试。"
        }
    }

    #if DEBUG
    private static func debugLogFetchedProfiles(_ fetchedProfiles: [FamilyProfile], label: String) {
        print("🔍 [FamilyDebug] \(label) — count=\(fetchedProfiles.count)")
        for profile in fetchedProfiles {
            print("🔍 调试档案 ID: \(profile.id) | 名字: \(profile.displayName)")
            print("   ↳ email: \(profile.email ?? "nil") | mainPhone: \(profile.mainPhone ?? "nil")")
            print("   ↳ 关联Membership: \(String(describing: profile.householdMemberships))")
            print("   ↳ 提取的Role: \(String(describing: profile.currentRole))")
            print("   ↳ 是否被判定为虚拟: \(profile.isVirtualUser)")
        }
    }

    private static func debugLogFetchedMemberships(_ memberships: [HouseholdMembership], label: String) {
        print("🔍 [FamilyDebug] \(label) — count=\(memberships.count)")
        for membership in memberships {
            print("   ↳ membership id=\(membership.id) profile_id=\(membership.profileId?.uuidString ?? "nil") role=\(membership.role ?? "nil") status=\(membership.status ?? "nil") nickname=\(membership.nickname ?? "nil")")
        }
    }
    #endif
}
