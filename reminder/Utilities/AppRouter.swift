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
    @Published private(set) var selectableHouseholds: [HouseholdOption] = []
    @Published private(set) var recentHouseholds: [HouseholdOption] = []
    @Published private(set) var selectedHouseholdId: UUID?
    @Published private(set) var selectedMembershipId: UUID?
    /// 当前用户在 `location_states` 中的 `entity_id`（`family_profiles.id`）。
    @Published private(set) var selectedProfileId: UUID?
    @Published private(set) var selectedHouseholdName: String?
    @Published private(set) var selectedHouseholdDescription: String = ""
    @Published private(set) var userEntitlement: UserEntitlement?
    @Published private(set) var selectedHouseholdIsPremium = false

    @Published var showNewCreatorAlert = false
    @Published var newlyAssignedHousehold: JoinedHousehold?

    /// 通知点击后等待各列表页消费的“打开任务详情”路由信息。
    @Published var pendingTaskReminderTap: TaskReminderNotificationUserInfo.Tap?

    /// 下次 `refreshStateFromBackend()` 完成后优先激活的组织（如刚创建的家庭）。
    private var pendingPreferredHouseholdId: UUID?

    private struct OfflineHouseholdSnapshot: Codable {
        let householdId: UUID
        let membershipId: UUID?
        let profileId: UUID?
        let householdName: String?
        let householdDescription: String
        let householdIsPremium: Bool
    }

    struct HouseholdOption: Identifiable, Equatable {
        let id: UUID
        let membershipId: UUID
        let profileId: UUID?
        let name: String
        var isPremium: Bool
        var description: String
    }

    /// 当前上下文是否享有 Pro / Premium 能力（个人权益或群组继承）。
    var hasPremiumAccess: Bool {
        PremiumAccess.hasPremiumAccess(
            userEntitlement: userEntitlement,
            householdIsPremium: selectedHouseholdIsPremium
        )
    }

    func preferHouseholdOnNextRefresh(_ householdId: UUID) {
        pendingPreferredHouseholdId = householdId
    }

    func consumePendingTaskReminderTap() {
        pendingTaskReminderTap = nil
    }

    /// 离线冷启动时恢复上次组织上下文，保证任务列表可命中本地缓存。
    @discardableResult
    func restoreOfflineHouseholdContextIfNeeded() -> Bool {
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
        selectedHouseholdIsPremium = snapshot.householdIsPremium
        appState = .activeMember
        return true
    }

    func clearOfflineHouseholdSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.offlineHouseholdSnapshotKey)
    }

    func refreshStateFromBackend() async {
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
            await loadUserEntitlement(userId: userId)
            recentHouseholds = sortHouseholdsByRecentUsage(options, userId: userId)

            guard activeMemberships.isEmpty == false else {
                if memberships.contains(where: { ["invited", "pending"].contains(normalizeStatus($0.status)) }) {
                    appState = .pendingApproval
                    debugLog("route.pendingApproval reason=no_active_membership")
                } else {
                    appState = .householdSelection
                    debugLog("route.householdSelection reason=no_active_membership")
                }
                selectableHouseholds = []
                recentHouseholds = []
                selectedHouseholdId = nil
                selectedMembershipId = nil
        selectedProfileId = nil
                selectedHouseholdName = nil
                selectedHouseholdDescription = ""
                selectedHouseholdIsPremium = false
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
                return
            }

            if options.count == 1, let onlyOption = options.first {
                debugLog("route.activeMember reason=single_household household=\(onlyOption.id.uuidString)")
                selectHouseholdAndEnter(
                    option: onlyOption,
                    userId: userId
                )
                return
            }

            if let lastHouseholdId = loadLastHouseholdId(for: userId),
               let lastOption = options.first(where: { $0.id == lastHouseholdId }) {
                debugLog("route.activeMember reason=last_household household=\(lastOption.id.uuidString)")
                selectHouseholdAndEnter(
                    option: lastOption,
                    userId: userId
                )
                return
            }

            selectedHouseholdId = nil
            selectedMembershipId = nil
        selectedProfileId = nil
            selectedHouseholdName = nil
            selectedHouseholdDescription = ""
            selectedHouseholdIsPremium = false
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
                selectedHouseholdIsPremium = false
                debugLog("route.unauthenticated reason=auth_error")
            } else if appState == .unauthenticated {
                // 已有会话但拉取组织状态失败时，进入群组选择页，避免卡在登录页死循环。
                appState = .householdSelection
                debugLog("route.householdSelection reason=non_auth_error_while_unauthenticated")
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
        selectedHouseholdIsPremium = false
        userEntitlement = nil
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
        selectedHouseholdIsPremium = false
    }

    func goToActiveMember() {
        appState = .activeMember
    }

    /// 解散家庭后清空当前组织上下文并回到入口枢纽页。
    func exitToOrgHubAfterDisband() {
        selectedHouseholdId = nil
        selectedMembershipId = nil
        selectedProfileId = nil
        selectedHouseholdName = nil
        selectedHouseholdDescription = ""
        selectableHouseholds = []
        appState = .householdSelection
        #if DEBUG
        print("[AppRouter] route.householdSelection reason=household_disbanded")
        #endif
    }

    /// 退出群组后：若仍有其他群组则进入第一个；否则回到创建/加入入口。
    func routeAfterLeavingHousehold(_ leftHouseholdId: UUID) async {
        #if canImport(Supabase)
        pendingPreferredHouseholdId = nil
        await refreshStateFromBackend()

        let remaining = selectableHouseholds.filter { $0.id != leftHouseholdId }
        guard let first = remaining.first else {
            goToHouseholdSelection()
            #if DEBUG
            print("[AppRouter] route.householdSelection reason=household_left_no_remaining")
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
        let option = HouseholdOption(
            id: joined.householdId,
            membershipId: joined.id,
            profileId: joined.profileId,
            name: joined.displayHouseholdName,
            isPremium: joined.household?.isPremium == true,
            description: ""
        )
        chooseHousehold(option)
    }

    /// 领取 Pro 后刷新个人权益、群组 Premium 标记与组织列表。
    func refreshPremiumStateAfterClaim() async {
        #if canImport(Supabase)
        do {
            let userId = try await SupabaseManager.shared.client.auth.session.user.id
            await loadUserEntitlement(userId: userId)
            if let householdId = selectedHouseholdId {
                await refreshHouseholdPremiumFlag(householdId: householdId)
            }
            await refreshStateFromBackend()
        } catch {
            debugLog("refreshPremiumStateAfterClaim.error \(error.localizedDescription)")
        }
        #endif
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

    /// 与 UserDefaults 快照比对，检测是否新获得某家庭的创建者权限。
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
    }

    private struct HouseholdRow: Decodable {
        let id: UUID
        let name: String
        let description: String?
        let isPremium: Bool?
    }

    private func loadUserEntitlement(userId: UUID) async {
        do {
            userEntitlement = try await SubscriptionSupabaseSupport.fetchUserEntitlement(userId: userId)
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
                .select("id,name,description,is_premium")
                .eq("id", value: householdId.uuidString.lowercased())
                .limit(1)
                .execute()
                .value
            guard let household = rows.first else { return }
            selectedHouseholdName = household.name
            selectedHouseholdDescription = household.description ?? ""
            selectedHouseholdIsPremium = household.isPremium == true
        } catch {
            debugLog("refreshSelectedHouseholdSnapshot.error \(error.localizedDescription)")
        }
        #endif
    }

    private func refreshHouseholdPremiumFlag(householdId: UUID) async {
        await refreshSelectedHouseholdSnapshot()
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
                .select("id,name,description,is_premium")
                .eq("id", value: householdID.uuidString)
                .limit(1)
                .execute()
                .value

            if let household = rows.first {
                debugLog("query.household_by_id.hit household=\(household.id.uuidString) name=\(household.name)")
                options.append(
                    .init(
                        id: household.id,
                        membershipId: membership.id,
                        profileId: membership.profileId,
                        name: household.name,
                        isPremium: household.isPremium == true,
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
                        name: "群组 \(householdID.uuidString.prefix(6))",
                        isPremium: false,
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
        selectedHouseholdIsPremium = option.isPremium
        saveLastHouseholdId(option.id, for: userId)
        saveRecentHouseholdId(option.id, for: userId)
        saveOfflineHouseholdSnapshot(option: option)
        appState = .activeMember
    }

    #if canImport(Supabase)
    private func clientHasPersistedSession() -> Bool {
        SupabaseManager.shared.client.auth.currentSession != nil
    }
    #else
    private func clientHasPersistedSession() -> Bool { false }
    #endif

    private func saveOfflineHouseholdSnapshot(option: HouseholdOption) {
        let snapshot = OfflineHouseholdSnapshot(
            householdId: option.id,
            membershipId: option.membershipId,
            profileId: option.profileId,
            householdName: option.name,
            householdDescription: option.description,
            householdIsPremium: option.isPremium
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.offlineHouseholdSnapshotKey)
        }
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
