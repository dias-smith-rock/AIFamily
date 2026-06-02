import Foundation
import Combine
#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class OrgRoutingViewModel: ObservableObject {
    @Published private(set) var isCreating = false
    @Published private(set) var isJoining = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var joinedHouseholds: [JoinedHousehold] = []
    @Published private(set) var isLoading = true

    @Published var showSignOutAlert = false
    @Published var showDeleteAccountAlert = false
    @Published var isProcessingAuth = false
    @Published var authErrorMessage: String?

    private let householdRoutingService: HouseholdRoutingService
    private let authService: AuthService

    init(
        householdRoutingService: HouseholdRoutingService,
        authService: AuthService
    ) {
        self.householdRoutingService = householdRoutingService
        self.authService = authService
    }

    func fetchMyHouseholds(appRouter: AppRouter) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await householdRoutingService.fetchMyJoinedHouseholds()
            joinedHouseholds = response.filter { household in
                household.isSelectable
                    && household.household?.isArchivedOrDeleted == false
            }
            await appRouter.checkForNewCreatorRoles(fetchedHouseholds: joinedHouseholds)
            #if DEBUG
            print("✅ [OrgHub] fetchMyHouseholds — count=\(joinedHouseholds.count)")
            #endif
        } catch {
            print("拉取家庭列表失败: \(error)")
            joinedHouseholds = []
        }
    }

    func createHousehold(
        displayName: String,
        description: String? = nil,
        isPremium: Bool = false
    ) async -> UUID? {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            let householdId = try await householdRoutingService.createHousehold(
                displayName: displayName,
                description: description
            )
            await CreatorRoleSnapshotStore.markKnownCreatorHouseholdIfPossible(householdId)
            AnalyticsManager.log(event: .groupCreated(groupId: householdId, isPremium: isPremium))
            return householdId
        } catch {
            errorMessage = mapErrorMessage(error, action: .create)
            return nil
        }
    }

    func joinHousehold(inviteCode: String) async -> Bool {
        isJoining = true
        errorMessage = nil
        defer { isJoining = false }

        do {
            try await householdRoutingService.joinHousehold(inviteCode: inviteCode)
            return true
        } catch let routingError as HouseholdRoutingError {
            errorMessage = mapHouseholdRoutingError(routingError)
            return false
        } catch {
            #if canImport(Supabase)
            if let dbError = error as? PostgrestError {
                errorMessage = mapPostgrestJoinError(dbError)
                return false
            }
            #endif
            #if DEBUG
            print("Unknown join error: \(error)")
            #endif
            errorMessage = Copy.networkError
            return false
        }
    }

    /// 邀请码加入群组：供组织切换菜单复用。
    func joinGroup(code: String) async -> Bool {
        await joinHousehold(inviteCode: code)
    }

    func acknowledgeError() {
        errorMessage = nil
    }

    func signOut(appRouter: AppRouter) async -> Bool {
        guard isProcessingAuth == false else { return false }
        isProcessingAuth = true
        authErrorMessage = nil
        defer { isProcessingAuth = false }

        AuthSessionGuard.shared.beginLoggingOut()
        do {
            try await authService.signOut()
            UserDefaults.standard.set(false, forKey: "isUserLoggedIn")
            UserDefaults.standard.removeObject(forKey: AppRouter.offlineHouseholdSnapshotKey)
            LocalCacheManager.shared.removeAll()
            await appRouter.refreshStateFromBackend()
            await AuthSessionGuard.shared.endLoggingOut()
            return true
        } catch {
            #if DEBUG
            print("退出登录失败: \(error)")
            #endif
            authErrorMessage = error.localizedDescription
            await AuthSessionGuard.shared.endLoggingOut()
            return false
        }
    }

    func deleteAccount(appRouter: AppRouter) async -> Bool {
        guard isProcessingAuth == false else { return false }
        isProcessingAuth = true
        authErrorMessage = nil
        defer { isProcessingAuth = false }

        AuthSessionGuard.shared.beginLoggingOut()
        do {
            // 预留：接入 delete-account Edge Function / RPC 后在此调用
            // try await supabase.functions.invoke("delete-account")
            await authService.cleanUpCurrentUserAvatars()
            try await authService.signOut()
            UserDefaults.standard.set(false, forKey: "isUserLoggedIn")
            UserDefaults.standard.removeObject(forKey: AppRouter.offlineHouseholdSnapshotKey)
            LocalCacheManager.shared.removeAll()
            await appRouter.refreshStateFromBackend()
            await AuthSessionGuard.shared.endLoggingOut()
            return true
        } catch {
            #if DEBUG
            print("注销账号失败: \(error)")
            #endif
            authErrorMessage = error.localizedDescription
            await AuthSessionGuard.shared.endLoggingOut()
            return false
        }
    }

    private enum ActionType {
        case create
        case join
    }

    private enum Copy {
        static let networkError = String(localized: "网络连接错误。请检查您的连接并重试。")
        static let createHouseholdFailed = String(localized: "创建群组失败，请稍后重试。")
        static let joinHouseholdFailed = String(localized: "加入群组失败，请稍后重试或联系群组创建者。")
        static let emptyHouseholdName = String(localized: "群组名称不能为空，请输入后再创建。")
        static let invalidInviteCode = String(localized: "邀请码无效。请检查并重试。")
        static let sessionExpired = String(localized: "您的登录会话已过期。请重新登录。")
        static let forbidden = String(localized: "您无权执行此操作。")
        static let householdNotFound = String(localized: "群组不存在或已被删除，请刷新后重试。")
        static let backendMigrationRequired = String(localized: "需要后端升级。请应用最新的 Supabase 迁移并重试。")
        static let alreadyMember = String(localized: "您已经加入了该群组，无需重复添加。")
        static let joinRequestPending = String(localized: "您的加入请求已提交。请等待管理员批准。")
        static let inviteCodeExpired = String(localized: "该邀请码已过期。请创建者分享一个新的。")
        static let inviteLinkUsed = String(localized: "该邀请链接已被使用。请向管理员询问新的。")
        static let householdNameMismatch = String(localized: "群组名称不匹配，请重新输入。")
        static let disbandUnauthorized = String(localized: "只有创建者才能解散该群组。")
        static let unknownError = String(localized: "出了点问题。请稍后重试。")
    }

    private func mapErrorMessage(_ error: Error, action: ActionType) -> String {
        if let routingError = error as? HouseholdRoutingError {
            return mapHouseholdRoutingError(routingError)
        }

        switch action {
        case .create:
            #if DEBUG
            print("创建家庭失败: \(error)")
            #endif
            return Copy.createHouseholdFailed
        case .join:
            #if DEBUG
            print("加入家庭失败: \(error)")
            #endif
            return Copy.joinHouseholdFailed
        }
    }

    private func mapHouseholdRoutingError(_ error: HouseholdRoutingError) -> String {
        switch error {
        case .invalidHouseholdName:
            return Copy.emptyHouseholdName
        case .householdNameTaken:
            return Copy.createHouseholdFailed
        case .invalidInviteCode:
            return Copy.invalidInviteCode
        case .unauthenticated:
            return Copy.sessionExpired
        case .forbidden:
            return Copy.forbidden
        case .householdNotFound:
            return Copy.householdNotFound
        case .backendMigrationRequired:
            return Copy.backendMigrationRequired
        case .alreadyActiveMember:
            return Copy.alreadyMember
        case .joinRequestPending:
            return Copy.joinRequestPending
        case .nonceExpired:
            return Copy.inviteCodeExpired
        case .nonceConsumed:
            return Copy.inviteLinkUsed
        case .networkFailure:
            return Copy.networkError
        case .householdNameMismatch:
            return Copy.householdNameMismatch
        case .disbandUnauthorized:
            return Copy.disbandUnauthorized
        case .creatorCannotLeave:
            return String(localized: "您是此群组的创建者。退出前请先转移所有权或解散群组。")
        case .transferUnauthorized, .transferInvalidTarget:
            return Copy.unknownError
        case .unknown:
            return Copy.joinHouseholdFailed
        }
    }

    #if canImport(Supabase)
    private func mapPostgrestJoinError(_ error: PostgrestError) -> String {
        let loweredMessage = error.message.lowercased()

        if error.code == "PGRST116" || loweredMessage.contains("not found") {
            return Copy.invalidInviteCode
        }
        if loweredMessage.contains("already_member") || loweredMessage.contains("already_active_member") {
            return Copy.alreadyMember
        }
        if loweredMessage.contains("expired") {
            return Copy.inviteCodeExpired
        }

        #if DEBUG
        print("DB Error: \(error.message)")
        #endif
        return Copy.joinHouseholdFailed
    }
    #endif
}
