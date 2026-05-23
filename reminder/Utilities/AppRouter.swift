import Foundation
import Combine

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class AppRouter: ObservableObject {
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
    @Published private(set) var selectedHouseholdName: String?

    /// 下次 `refreshStateFromBackend()` 完成后优先激活的组织（如刚创建的家庭）。
    private var pendingPreferredHouseholdId: UUID?

    struct HouseholdOption: Identifiable, Equatable {
        let id: UUID
        let membershipId: UUID
        let name: String
    }

    func preferHouseholdOnNextRefresh(_ householdId: UUID) {
        pendingPreferredHouseholdId = householdId
    }

    func refreshStateFromBackend() async {
        #if canImport(Supabase)
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
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
                selectedHouseholdName = nil
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
            selectedHouseholdName = nil
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
                selectedHouseholdName = nil
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
        selectedHouseholdName = nil
        selectableHouseholds = []
        recentHouseholds = []
    }

    func goToPendingApproval() {
        appState = .pendingApproval
        selectedHouseholdId = nil
        selectedMembershipId = nil
        selectedHouseholdName = nil
        selectableHouseholds = []
        recentHouseholds = []
    }

    func goToActiveMember() {
        appState = .activeMember
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
        let status: String
    }

    private struct HouseholdRow: Decodable {
        let id: UUID
        let name: String
    }

    private func fetchMemberships(client: SupabaseClient, userId: UUID) async throws -> [MembershipRow] {
        debugLog("query.memberships.start user=\(userId.uuidString)")
        let rows: [MembershipRow] = try await client
            .from("household_memberships")
            .select("id,household_id,status")
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
                .select("id,name")
                .eq("id", value: householdID.uuidString)
                .limit(1)
                .execute()
                .value

            if let household = rows.first {
                debugLog("query.household_by_id.hit household=\(household.id.uuidString) name=\(household.name)")
                options.append(.init(id: household.id, membershipId: membership.id, name: household.name))
            } else {
                debugLog("query.household_by_id.miss household=\(householdID.uuidString)")
                options.append(.init(id: householdID, membershipId: membership.id, name: "家庭 \(householdID.uuidString.prefix(6))"))
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
        selectedHouseholdName = option.name
        saveLastHouseholdId(option.id, for: userId)
        saveRecentHouseholdId(option.id, for: userId)
        appState = .activeMember
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
