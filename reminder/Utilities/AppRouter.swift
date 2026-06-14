import Foundation
import Combine

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class AppRouter: ObservableObject {
    static let offlineHouseholdSnapshotKey = "aifamily.offline.household.snapshot"

    enum AppState: Equatable {
        case unauthenticated
        case orgRouting
        case householdSelection
        case pendingApproval
        case activeMember
    }

    @Published var appState: AppState = .unauthenticated
    /// `refreshStateFromBackend()` 是否已跑完一轮（含离线短路）；用于区分启动加载与鉴权失效。
    @Published private(set) var isAnonymousUser = false
    @Published private(set) var hasCompletedAuthBootstrap = false
    @Published private(set) var selectableHouseholds: [HouseholdOption] = []
    @Published private(set) var recentHouseholds: [HouseholdOption] = []
    @Published private(set) var selectedHouseholdId: UUID?
    @Published private(set) var selectedMembershipId: UUID?
    /// 当前用户在 `location_states` 中的 `entity_id`（`family_profiles.id`）。
    @Published private(set) var selectedProfileId: UUID?
    @Published private(set) var selectedHouseholdName: String?
    @Published private(set) var selectedHouseholdDescription: String = ""
    @Published private(set) var userEntitlement: UserEntitlement?
    @Published private(set) var authUserId: UUID?
    @Published private(set) var selectedHouseholdCreatorHasActivePro = false

    @Published var showNewCreatorAlert = false
    @Published var newlyAssignedHousehold: JoinedHousehold?

    /// 通知点击后等待各列表页消费的“打开任务详情”路由信息。
    @Published var pendingTaskReminderTap: TaskReminderNotificationUserInfo.Tap?

    /// 「我的」页创建者无法注销时，请求打开当前群组的群组设置页。
    @Published var pendingOpenGroupSettings = false

    /// 全局 VIP 升级页（免费版触达配额上限时由各处 `.alert` 触发）。
    @Published var isPresentingVIPUpgrade = false

    /// 下次 `refreshStateFromBackend()` 完成后优先激活的组织（如刚创建的群组）。
    private var pendingPreferredHouseholdId: UUID?

    /// OAuth 正式登录后：OrgRoutingView 展示群组信息加载蒙层。
    @Published private(set) var isResolvingHouseholdRouting = false

    /// OAuth `settleAfterOAuth` 已 refresh 时，跳过 `ContentView` 登录后重复 refresh。
    private var skipNextLoginBootstrapRefresh = false

    private var householdRoutingResolveRefreshFinished = false
    private var orgRoutingSurfaceDidAppear = false

    private struct OfflineHouseholdSnapshot: Codable {
        let householdId: UUID
        let membershipId: UUID?
        let profileId: UUID?
        let householdName: String?
        let householdDescription: String
        let creatorHasActivePro: Bool
    }

    struct HouseholdOption: Identifiable, Equatable {
        let id: UUID
        let membershipId: UUID
        let profileId: UUID?
        let name: String
        /// 该组织创建者是否享有有效 Pro（用于组织内继承判断）。
        var creatorHasActivePro: Bool
        var description: String

        func hasPremiumAccess(userEntitlement: UserEntitlement?) -> Bool {
            PremiumAccess.hasPremiumAccess(
                userEntitlement: userEntitlement,
                creatorHasActivePro: creatorHasActivePro
            )
        }
    }

    /// 当前上下文是否享有 Pro / Premium 能力（个人权益或当前组织创建者继承）。
    var hasPremiumAccess: Bool {
        return PremiumAccess.hasPremiumAccess(
            userEntitlement: userEntitlement,
            creatorHasActivePro: selectedHouseholdCreatorHasActivePro
        ) || RevenueCatSubscriptionService.shared.hasActiveProEntitlement
    }

    /// 本人是否享有 Pro（仅 `user_entitlements`，不含组织继承与游客放行）。
    var hasPersonalPremiumAccess: Bool {
        userEntitlement?.isActive == true
    }

    /// 设置页 / 订阅页是否展示「本人已订阅」（云端权益或本会话已确认的本机订阅）。
    var showsPersonalVIP: Bool {
        RevenueCatSubscriptionService.shared.isPersonalSubscriber(userEntitlement: userEntitlement)
    }

    /// 输出 VIP 三元诊断日志（创建者 VIP / 本人 VIP / 当前组织内 VIP）。
    func logVIPAccessState(trigger: String) {
        PremiumAccessDiagnostics.log(appRouter: self, trigger: trigger)
    }

    /// 当前 Pro 是否仅来自组织创建者继承（非个人 VIP）。
    var hasInheritedPremiumOnly: Bool {
        PremiumAccess.hasInheritedPremiumOnly(
            userEntitlement: userEntitlement,
            creatorHasActivePro: selectedHouseholdCreatorHasActivePro
        )
    }

    /// 免费版群组数校验：取已同步列表与 onboarding 拉取结果的较大值。
    func resolvedHouseholdCount(fallbackJoinedCount: Int = 0) -> Int {
        max(selectableHouseholds.count, fallbackJoinedCount)
    }

    func canCreateOrJoinAnotherHousehold(fallbackJoinedCount: Int = 0) -> Bool {
        PremiumLimits.canCreateOrJoinAnotherHousehold(
            currentCount: resolvedHouseholdCount(fallbackJoinedCount: fallbackJoinedCount),
            hasPremium: hasPremiumAccess
        )
    }

    func preferHouseholdOnNextRefresh(_ householdId: UUID) {
        pendingPreferredHouseholdId = householdId
    }

    func consumePendingTaskReminderTap() {
        pendingTaskReminderTap = nil
    }

    func requestOpenGroupSettings() {
        pendingOpenGroupSettings = true
    }

    func presentPremiumUpgrade() {
        isPresentingVIPUpgrade = true
    }

    func consumePendingOpenGroupSettingsRequest() {
        pendingOpenGroupSettings = false
    }

    /// Bootstrap 前同步 Keychain 会话身份（离线或未走完 refresh 时仍需正确游客标记）。
    func syncSessionIdentityFromPersistedSessionIfAvailable() {
        syncSessionIdentityFromKeychainIfAvailable()
    }

    /// OAuth / 正式账号切换前清空离线快照与组织路由，避免误恢复游客 household。
    func clearHouseholdRoutingForIdentitySwitch() {
        clearOfflineHouseholdSnapshot()
        prepareForSoftExitToLogin()
    }

    func beginHouseholdRoutingResolve() {
        isResolvingHouseholdRouting = true
        householdRoutingResolveRefreshFinished = false
        orgRoutingSurfaceDidAppear = false
    }

    /// refresh 完成后调用；若仍停留在群组路由页，须等 OrgRoutingView `onAppear` 再收起蒙层。
    func finishHouseholdRoutingResolveAfterRefresh() {
        householdRoutingResolveRefreshFinished = true
        dismissHouseholdRoutingResolveOverlayIfReady()
    }

    func notifyOrgRoutingSurfaceDidAppear() {
        guard isResolvingHouseholdRouting else { return }
        orgRoutingSurfaceDidAppear = true
        dismissHouseholdRoutingResolveOverlayIfReady()
    }

    private func dismissHouseholdRoutingResolveOverlayIfReady() {
        guard isResolvingHouseholdRouting, householdRoutingResolveRefreshFinished else { return }

        if appState != .orgRouting {
            clearHouseholdRoutingResolveState()
            return
        }

        guard orgRoutingSurfaceDidAppear else { return }
        clearHouseholdRoutingResolveState()
    }

    private func clearHouseholdRoutingResolveState() {
        isResolvingHouseholdRouting = false
        householdRoutingResolveRefreshFinished = false
        orgRoutingSurfaceDidAppear = false
    }

    func markOAuthBootstrapCompleted() {
        skipNextLoginBootstrapRefresh = true
    }

    func consumeSkipNextLoginBootstrapRefresh() -> Bool {
        guard skipNextLoginBootstrapRefresh else { return false }
        skipNextLoginBootstrapRefresh = false
        return true
    }

    /// 离线冷启动时恢复上次组织上下文，保证任务列表可命中本地缓存（仅游客会话）。
    @discardableResult
    func restoreOfflineHouseholdContextIfNeeded() -> Bool {
        syncSessionIdentityFromKeychainIfAvailable()
        guard isAnonymousUser else { return false }
        guard selectedHouseholdId == nil else { return false }
        guard
            let data = UserDefaults.standard.data(forKey: Self.offlineHouseholdSnapshotKey),
            let snapshot = try? JSONDecoder().decode(OfflineHouseholdSnapshot.self, from: data)
        else {
            return false
        }

        selectedHouseholdId = snapshot.householdId
        selectedMembershipId = snapshot.membershipId
        selectedProfileId = snapshot.profileId
        selectedHouseholdName = snapshot.householdName
        selectedHouseholdDescription = snapshot.householdDescription
        selectedHouseholdCreatorHasActivePro = snapshot.creatorHasActivePro
        appState = .activeMember
        return true
    }

    func clearOfflineHouseholdSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.offlineHouseholdSnapshotKey)
    }

    /// 本地是否仍存有 Supabase 会话（未必有效，离线启动时用于避免误踢回登录页）。
    var hasPersistedSupabaseSession: Bool {
        clientHasPersistedSession()
    }

    func refreshStateFromBackend() async {
        hasCompletedAuthBootstrap = false
        defer { hasCompletedAuthBootstrap = true }

        syncSessionIdentityFromKeychainIfAvailable()

        #if canImport(Supabase)
        if await NetworkMonitor.shared.isConnected == false {
            if clientHasPersistedSession(),
               appState == .activeMember,
               selectedHouseholdId != nil {
                debugLog("refresh.skipped reason=offline keepActiveMember")
                return
            }
            if clientHasPersistedSession(), AuthSessionHints.hasEverAuthenticated {
                if appState == .unauthenticated {
                    _ = restoreOfflineHouseholdContextIfNeeded()
                }
                debugLog("refresh.skipped reason=offline")
            }
            return
        }

        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            AuthSessionHints.markEverAuthenticated()
            isAnonymousUser = session.user.isAnonymous
            let userId = session.user.id
            let memberships = try await fetchMemberships(client: client, userId: userId)
            let activeMemberships = memberships.filter { normalizeStatus($0.status) == "active" }
            debugLog(
                "refresh.start user=\(userId.uuidString) memberships=\(memberships.count) active=\(activeMemberships.count) statuses=\(membershipStatusSummary(memberships))"
            )
            let options = try await fetchHouseholdOptions(
                client: client,
                memberships: activeMemberships
            )
            authUserId = userId
            await RevenueCatSubscriptionService.shared.logIn(userId: userId)
            await loadUserEntitlement(userId: userId)
            await RevenueCatSubscriptionService.shared.refreshCustomerInfo()
            if session.user.isAnonymous == false {
                await RevenueCatSubscriptionService.shared.syncEntitlementToCloudIfNeeded(appRouter: self)
            } else {
                Task {
                    await RevenueCatSubscriptionService.shared.syncEntitlementToCloudIfNeeded(appRouter: self)
                }
            }
            recentHouseholds = sortHouseholdsByRecentUsage(options, userId: userId)

            guard activeMemberships.isEmpty == false else {
                if memberships.contains(where: { ["invited", "pending"].contains(normalizeStatus($0.status)) }) {
                    appState = .pendingApproval
                    debugLog("route.pendingApproval reason=no_active_membership")
                } else {
                    appState = .orgRouting
                    debugLog("route.orgRouting reason=no_active_membership")
                }
                selectableHouseholds = []
                recentHouseholds = []
                selectedHouseholdId = nil
                selectedMembershipId = nil
        selectedProfileId = nil
                selectedHouseholdName = nil
                selectedHouseholdDescription = ""
                selectedHouseholdCreatorHasActivePro = false
                return
            }

            selectableHouseholds = options

            if let preferredId = pendingPreferredHouseholdId,
               let preferredOption = options.first(where: { $0.id == preferredId }) {
                pendingPreferredHouseholdId = nil
                debugLog("route.activeMember reason=preferred_after_create household=\(preferredOption.id.uuidString)")
                selectHouseholdAndEnter(
                    option: preferredOption,
                    userId: userId
                )
                await refreshSelectedHouseholdCreatorPro(householdId: preferredOption.id)
                return
            }

            if options.count == 1, let onlyOption = options.first {
                debugLog("route.activeMember reason=single_household household=\(onlyOption.id.uuidString)")
                selectHouseholdAndEnter(
                    option: onlyOption,
                    userId: userId
                )
                await refreshSelectedHouseholdCreatorPro(householdId: onlyOption.id)
                return
            }

            if let lastHouseholdId = loadLastHouseholdId(for: userId),
               let lastOption = options.first(where: { $0.id == lastHouseholdId }) {
                debugLog("route.activeMember reason=last_household household=\(lastOption.id.uuidString)")
                selectHouseholdAndEnter(
                    option: lastOption,
                    userId: userId
                )
                await refreshSelectedHouseholdCreatorPro(householdId: lastOption.id)
                return
            }

            if let currentId = selectedHouseholdId,
               let currentOption = options.first(where: { $0.id == currentId }) {
                debugLog("route.activeMember reason=current_selection household=\(currentOption.id.uuidString)")
                selectHouseholdAndEnter(
                    option: currentOption,
                    userId: userId
                )
                await refreshSelectedHouseholdCreatorPro(householdId: currentOption.id)
                return
            }

            if let snapshotOption = restoredOfflineHouseholdOption(in: options) {
                debugLog("route.activeMember reason=offline_snapshot household=\(snapshotOption.id.uuidString)")
                selectHouseholdAndEnter(
                    option: snapshotOption,
                    userId: userId
                )
                await refreshSelectedHouseholdCreatorPro(householdId: snapshotOption.id)
                return
            }

            selectedHouseholdId = nil
            selectedMembershipId = nil
        selectedProfileId = nil
            selectedHouseholdName = nil
            selectedHouseholdDescription = ""
            selectedHouseholdCreatorHasActivePro = false
            appState = .householdSelection
            debugLog("route.householdSelection reason=multiple_households options=\(options.count)")
        } catch {
            debugLog("refresh.error \(error.localizedDescription)")
            // 仅在鉴权确实失效时回退到登录页；
            // 其余瞬时错误（网络、解码、RLS 变更等）保持当前页面，避免错误踢回登录。
            if isAuthenticationError(error) {
                appState = .unauthenticated
                selectableHouseholds = []
                recentHouseholds = []
                selectedHouseholdId = nil
                selectedMembershipId = nil
        selectedProfileId = nil
                selectedHouseholdName = nil
                selectedHouseholdDescription = ""
                selectedHouseholdCreatorHasActivePro = false
                resetAuthenticatedPremiumState()
                debugLog("route.unauthenticated reason=auth_error")
            } else if appState == .unauthenticated {
                // 已有会话但拉取组织状态失败时，至少进入组织路由页，避免卡在登录页死循环。
                appState = .orgRouting
                debugLog("route.orgRouting reason=non_auth_error_while_unauthenticated")
            }
        }
        #else
        appState = .unauthenticated
        #endif
    }

    func goToOrgRouting() {
        appState = .orgRouting
        selectedHouseholdId = nil
        selectedMembershipId = nil
        selectedProfileId = nil
        selectedHouseholdName = nil
        selectedHouseholdDescription = ""
        selectedHouseholdCreatorHasActivePro = false
        selectableHouseholds = []
        recentHouseholds = []
        if isResolvingHouseholdRouting {
            orgRoutingSurfaceDidAppear = false
        }
    }

    /// 匿名登录成功后立即进入组织路由，避免 `isUserLoggedIn` 已 true 但 `appState` 仍为 `.unauthenticated` 时卡在加载页。
    func finishAnonymousSignIn(userId: UUID) {
        authUserId = userId
        isAnonymousUser = true
        if appState == .unauthenticated {
            goToOrgRouting()
        }
    }

    /// 游客软退出：回到登录页，不清 Keychain 会话。
    func prepareForSoftExitToLogin() {
        appState = .unauthenticated
        selectedHouseholdId = nil
        selectedMembershipId = nil
        selectedProfileId = nil
        selectedHouseholdName = nil
        selectedHouseholdDescription = ""
        selectedHouseholdCreatorHasActivePro = false
        selectableHouseholds = []
        recentHouseholds = []
    }

    func goToPendingApproval() {
        appState = .pendingApproval
        selectedHouseholdId = nil
        selectedMembershipId = nil
        selectedProfileId = nil
        selectedHouseholdName = nil
        selectedHouseholdDescription = ""
        selectableHouseholds = []
        recentHouseholds = []
    }

    /// 当通知目标组织已不存在时，回到组织选择页（保留最新可选组织列表）。
    func goToHouseholdSelection() {
        appState = .householdSelection
        selectedHouseholdId = nil
        selectedMembershipId = nil
        selectedProfileId = nil
        selectedHouseholdName = nil
        selectedHouseholdDescription = ""
        selectedHouseholdCreatorHasActivePro = false
    }

    func goToActiveMember() {
        appState = .activeMember
    }

    /// 解散群组后清空当前组织上下文并回到入口枢纽页。
    func exitToOrgHubAfterDisband() {
        selectedHouseholdId = nil
        selectedMembershipId = nil
        selectedProfileId = nil
        selectedHouseholdName = nil
        selectedHouseholdDescription = ""
        selectableHouseholds = []
        appState = .orgRouting
        #if DEBUG
        print("[AppRouter] route.orgRouting reason=household_disbanded")
        #endif
    }

    /// 退出群组后：若仍有其他群组则进入第一个；否则回到创建/加入入口。
    func routeAfterLeavingHousehold(_ leftHouseholdId: UUID) async {
        #if canImport(Supabase)
        pendingPreferredHouseholdId = nil
        await refreshStateFromBackend()

        let remaining = selectableHouseholds.filter { $0.id != leftHouseholdId }
        guard let first = remaining.first else {
            goToOrgRouting()
            #if DEBUG
            print("[AppRouter] route.orgRouting reason=household_left_no_remaining")
            #endif
            return
        }

        chooseHousehold(first)
        #if DEBUG
        print("[AppRouter] route.activeMember reason=household_left_fallback household=\(first.id.uuidString)")
        #endif
        #else
        _ = leftHouseholdId
        goToOrgRouting()
        #endif
    }

    func chooseJoinedHousehold(_ joined: JoinedHousehold) {
        #if canImport(Supabase)
        Task {
            let creatorHasActivePro: Bool
            do {
                creatorHasActivePro = try await SubscriptionSupabaseSupport.fetchHouseholdCreatorHasActivePro(
                    householdId: joined.householdId
                )
            } catch {
                debugLog(
                    "fetchHouseholdCreatorHasActivePro.error household=\(joined.householdId.uuidString) \(error.localizedDescription)"
                )
                print(
                    "[VIPAccess] household_creator_has_active_pro 失败 household=\(joined.householdId.uuidString.prefix(8)) error=\(error.localizedDescription)"
                )
                creatorHasActivePro = false
            }
            let option = HouseholdOption(
                id: joined.householdId,
                membershipId: joined.id,
                profileId: joined.profileId,
                name: joined.displayHouseholdName,
                creatorHasActivePro: creatorHasActivePro,
                description: ""
            )
            chooseHousehold(option)
        }
        #else
        let option = HouseholdOption(
            id: joined.householdId,
            membershipId: joined.id,
            profileId: joined.profileId,
            name: joined.displayHouseholdName,
            creatorHasActivePro: false,
            description: ""
        )
        chooseHousehold(option)
        #endif
    }

    /// 购买/恢复服务端校验通过后，先乐观更新本人权益，再拉取云端真相。
    func applyOptimisticPersonalEntitlement(userId: UUID, expiresAt: Date?) {
        authUserId = userId
        userEntitlement = UserEntitlement(userId: userId, isPro: true, proExpiresAt: expiresAt)
    }

    /// 解析当前登录用户 ID（bootstrap 未完成时从 session 补全）。
    func resolveAuthUserId() async -> UUID? {
        if let authUserId {
            return authUserId
        }
        #if canImport(Supabase)
        do {
            let userId = try await SupabaseManager.shared.client.auth.session.user.id
            authUserId = userId
            return userId
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// 领取 Pro 后刷新个人权益、群组 Premium 标记与组织列表。
    func refreshPremiumStateAfterClaim() async {
        #if canImport(Supabase)
        do {
            let userId = try await SupabaseManager.shared.client.auth.session.user.id
            authUserId = userId
            await loadUserEntitlement(userId: userId)
            await RevenueCatSubscriptionService.shared.refreshCustomerInfo()
            if let householdId = selectedHouseholdId {
                await refreshSelectedHouseholdCreatorPro(householdId: householdId)
            }
        } catch {
            debugLog("refreshPremiumStateAfterClaim.error \(error.localizedDescription)")
        }
        #endif
    }

    private func resetAuthenticatedPremiumState() {
        authUserId = nil
        isAnonymousUser = false
        userEntitlement = nil
        Task {
            await RevenueCatSubscriptionService.shared.logOut()
        }
    }

    func dismissNewCreatorAlert() {
        showNewCreatorAlert = false
        newlyAssignedHousehold = nil
    }

    func enterNewlyAssignedCreatorHousehold() {
        guard let joined = newlyAssignedHousehold else { return }
        showNewCreatorAlert = false
        newlyAssignedHousehold = nil
        chooseJoinedHousehold(joined)
    }

    /// 与 UserDefaults 快照比对，检测是否新获得某群组的创建者权限。
    func checkForNewCreatorRoles(fetchedHouseholds: [JoinedHousehold]) async {
        guard let userId = await CreatorRoleSnapshotStore.currentUserId() else { return }

        if let newHousehold = CreatorRoleSnapshotStore.newlyAssignedCreatorHousehold(
            in: fetchedHouseholds,
            userId: userId
        ) {
            newlyAssignedHousehold = newHousehold
            showNewCreatorAlert = true
        }
    }

    func chooseHousehold(_ option: HouseholdOption) {
        #if canImport(Supabase)
        Task {
            do {
                let userId = try await SupabaseManager.shared.client.auth.session.user.id
                await MainActor.run {
                    self.selectHouseholdAndEnter(
                        option: option,
                        userId: userId
                    )
                }
                await self.refreshSelectedHouseholdCreatorPro(householdId: option.id)
                await MainActor.run {
                    self.logVIPAccessState(trigger: L10n.Family.switchOrganization.string())
                }
            } catch {
                await MainActor.run {
                    self.appState = .unauthenticated
                }
            }
        }
        #else
        appState = .activeMember
        #endif
    }

    #if canImport(Supabase)
    private struct MembershipRow: Decodable {
        let id: UUID
        let householdId: UUID
        let profileId: UUID?
        let status: String

        enum CodingKeys: String, CodingKey {
            case id
            case householdId
            case profileId
            case status
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            householdId = try container.decode(UUID.self, forKey: .householdId)
            profileId = try container.decodeIfPresent(UUID.self, forKey: .profileId)
            status = try container.decode(String.self, forKey: .status)
        }
    }

    private struct HouseholdRow: Decodable {
        let id: UUID
        let name: String
        let description: String?
    }

    private func loadUserEntitlement(userId: UUID) async {
        do {
            if let fetched = try await SubscriptionSupabaseSupport.fetchUserEntitlement(userId: userId) {
                userEntitlement = fetched
            } else {
                userEntitlement = UserEntitlement(userId: userId, isPro: false, proExpiresAt: nil)
            }
        } catch {
            debugLog("loadUserEntitlement.error \(error.localizedDescription)")
        }
    }

    func refreshSelectedHouseholdSnapshot() async {
        #if canImport(Supabase)
        guard await NetworkMonitor.shared.isConnected else { return }
        guard let householdId = selectedHouseholdId else { return }
        do {
            let rows: [HouseholdRow] = try await SupabaseManager.shared.client
                .from("households")
                .select("id,name,description")
                .eq("id", value: householdId.uuidString.lowercased())
                .limit(1)
                .execute()
                .value
            guard let household = rows.first else { return }
            selectedHouseholdName = household.name
            selectedHouseholdDescription = household.description ?? ""
            await refreshSelectedHouseholdCreatorPro(householdId: householdId)
        } catch {
            debugLog("refreshSelectedHouseholdSnapshot.error \(error.localizedDescription)")
        }
        #endif
    }

    private func refreshSelectedHouseholdCreatorPro(householdId: UUID) async {
        do {
            selectedHouseholdCreatorHasActivePro = try await SubscriptionSupabaseSupport
                .fetchHouseholdCreatorHasActivePro(householdId: householdId)
            syncCreatorHasActiveProInHouseholdLists(householdId: householdId)
        } catch {
            debugLog(
                "refreshSelectedHouseholdCreatorPro.error household=\(householdId.uuidString) \(error.localizedDescription)"
            )
            print(
                "[VIPAccess] refreshSelectedHouseholdCreatorPro 失败 household=\(householdId.uuidString.prefix(8)) error=\(error.localizedDescription)"
            )
            selectedHouseholdCreatorHasActivePro = false
        }
    }

    private func syncCreatorHasActiveProInHouseholdLists(householdId: UUID) {
        let value = selectedHouseholdCreatorHasActivePro
        selectableHouseholds = selectableHouseholds.map { option in
            guard option.id == householdId else { return option }
            var updated = option
            updated.creatorHasActivePro = value
            return updated
        }
        recentHouseholds = recentHouseholds.map { option in
            guard option.id == householdId else { return option }
            var updated = option
            updated.creatorHasActivePro = value
            return updated
        }
    }

    private func fetchMemberships(client: SupabaseClient, userId: UUID) async throws -> [MembershipRow] {
        debugLog("query.memberships.start user=\(userId.uuidString)")
        let rows: [MembershipRow] = try await client
            .from("household_memberships")
            .select("id,household_id,profile_id,status")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        debugLog("query.memberships.success count=\(rows.count)")
        return rows
    }

    private func fetchHouseholdOptions(client: SupabaseClient, memberships: [MembershipRow]) async throws -> [HouseholdOption] {
        debugLog("query.household_options.start memberships=\(memberships.count)")
        var options: [HouseholdOption] = []
        let uniqueHouseholdIDs = Array(Set(memberships.map(\.householdId)))
        for householdID in uniqueHouseholdIDs {
            guard let membership = memberships.first(where: { $0.householdId == householdID }) else {
                continue
            }
            debugLog("query.household_by_id.start household=\(householdID.uuidString)")
            let rows: [HouseholdRow] = try await client
                .from("households")
                .select("id,name,description")
                .eq("id", value: householdID.uuidString)
                .limit(1)
                .execute()
                .value

            let creatorHasActivePro: Bool
            do {
                creatorHasActivePro = try await SubscriptionSupabaseSupport.fetchHouseholdCreatorHasActivePro(
                    householdId: householdID
                )
            } catch {
                debugLog(
                    "fetchHouseholdCreatorHasActivePro.error household=\(householdID.uuidString) \(error.localizedDescription)"
                )
                print(
                    "[VIPAccess] household_creator_has_active_pro 失败 household=\(householdID.uuidString.prefix(8)) error=\(error.localizedDescription)"
                )
                creatorHasActivePro = false
            }

            if let household = rows.first {
                debugLog("query.household_by_id.hit household=\(household.id.uuidString) name=\(household.name)")
                options.append(
                    .init(
                        id: household.id,
                        membershipId: membership.id,
                        profileId: membership.profileId,
                        name: household.name,
                        creatorHasActivePro: creatorHasActivePro,
                        description: household.description ?? ""
                    )
                )
            } else {
                debugLog("query.household_by_id.miss household=\(householdID.uuidString)")
                options.append(
                    .init(
                        id: householdID,
                        membershipId: membership.id,
                        profileId: membership.profileId,
                        name: "Group \(householdID.uuidString.prefix(6))",
                        creatorHasActivePro: false,
                        description: ""
                    )
                )
            }
        }
        let sorted = options.sorted { $0.name < $1.name }
        debugLog("query.household_options.success count=\(sorted.count)")
        return sorted
    }

    private func normalizeStatus(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func selectHouseholdAndEnter(option: HouseholdOption, userId: UUID) {
        selectedHouseholdId = option.id
        selectedMembershipId = option.membershipId
        selectedProfileId = option.profileId
        selectedHouseholdName = option.name
        selectedHouseholdDescription = option.description
        selectedHouseholdCreatorHasActivePro = option.creatorHasActivePro
        saveLastHouseholdId(option.id, for: userId)
        saveRecentHouseholdId(option.id, for: userId)
        saveOfflineHouseholdSnapshot(option: option)
        appState = .activeMember
    }

    #if canImport(Supabase)
    private func clientHasPersistedSession() -> Bool {
        SupabaseManager.shared.client.auth.currentSession != nil
    }

    /// 从 Keychain 已持久化的 Supabase 会话同步游客标记（离线短路或未走完 refresh 时仍需正确 UI）。
    private func syncSessionIdentityFromKeychainIfAvailable() {
        guard let session = SupabaseManager.shared.client.auth.currentSession else { return }
        isAnonymousUser = session.user.isAnonymous
        authUserId = session.user.id
    }
    #else
    private func clientHasPersistedSession() -> Bool { false }

    private func syncSessionIdentityFromKeychainIfAvailable() {}
    #endif

    private func saveOfflineHouseholdSnapshot(option: HouseholdOption) {
        let snapshot = OfflineHouseholdSnapshot(
            householdId: option.id,
            membershipId: option.membershipId,
            profileId: option.profileId,
            householdName: option.name,
            householdDescription: option.description,
            creatorHasActivePro: option.creatorHasActivePro
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.offlineHouseholdSnapshotKey)
        }
    }

    private func restoredOfflineHouseholdOption(in options: [HouseholdOption]) -> HouseholdOption? {
        guard
            let data = UserDefaults.standard.data(forKey: Self.offlineHouseholdSnapshotKey),
            let snapshot = try? JSONDecoder().decode(OfflineHouseholdSnapshot.self, from: data)
        else {
            return nil
        }
        return options.first(where: { $0.id == snapshot.householdId })
    }

    private func saveLastHouseholdId(_ householdId: UUID, for userId: UUID) {
        UserDefaults.standard.set(householdId.uuidString, forKey: lastHouseholdKey(for: userId))
    }

    private func loadLastHouseholdId(for userId: UUID) -> UUID? {
        guard let stored = UserDefaults.standard.string(forKey: lastHouseholdKey(for: userId)) else {
            return nil
        }
        return UUID(uuidString: stored)
    }

    private func saveRecentHouseholdId(_ householdId: UUID, for userId: UUID) {
        var ids = loadRecentHouseholdIds(for: userId)
        ids.removeAll(where: { $0 == householdId })
        ids.insert(householdId, at: 0)
        let trimmed = Array(ids.prefix(5)).map(\.uuidString)
        UserDefaults.standard.set(trimmed, forKey: recentHouseholdsKey(for: userId))
    }

    private func loadRecentHouseholdIds(for userId: UUID) -> [UUID] {
        let key = recentHouseholdsKey(for: userId)
        let rawStrings = UserDefaults.standard.stringArray(forKey: key) ?? []

        let parsed = rawStrings.compactMap(UUID.init(uuidString:))
        var seen: Set<UUID> = []
        var sanitized: [UUID] = []
        sanitized.reserveCapacity(min(parsed.count, 5))

        for id in parsed where seen.contains(id) == false {
            seen.insert(id)
            sanitized.append(id)
            if sanitized.count == 5 { break }
        }

        let sanitizedStrings = sanitized.map(\.uuidString)
        if sanitizedStrings != rawStrings {
            UserDefaults.standard.set(sanitizedStrings, forKey: key)
            debugLog("recent_households.sanitized user=\(userId.uuidString) before=\(rawStrings.count) after=\(sanitizedStrings.count)")
        }

        return sanitized
    }

    private func sortHouseholdsByRecentUsage(_ options: [HouseholdOption], userId: UUID) -> [HouseholdOption] {
        let recent = loadRecentHouseholdIds(for: userId)
        var order: [UUID: Int] = [:]
        for (index, id) in recent.enumerated() where order[id] == nil {
            order[id] = index
        }
        return options.sorted { lhs, rhs in
            let l = order[lhs.id] ?? Int.max
            let r = order[rhs.id] ?? Int.max
            if l != r { return l < r }
            return lhs.name < rhs.name
        }
    }

    private func lastHouseholdKey(for userId: UUID) -> String {
        "aifamily.lastHousehold.\(userId.uuidString)"
    }

    private func recentHouseholdsKey(for userId: UUID) -> String {
        "aifamily.recentHouseholds.\(userId.uuidString)"
    }

    private func isAuthenticationError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("jwt")
            || message.contains("session")
            || message.contains("unauthenticated")
            || message.contains("invalid refresh token")
            || message.contains("auth")
    }

    private func membershipStatusSummary(_ memberships: [MembershipRow]) -> String {
        guard memberships.isEmpty == false else { return "none" }
        return memberships
            .map { "\($0.id.uuidString.prefix(6)):\(normalizeStatus($0.status))" }
            .joined(separator: ",")
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[AppRouter] \(message)")
        #endif
    }
    #endif
}
