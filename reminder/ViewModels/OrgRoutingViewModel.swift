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
            print("拉取群组列表失败: \(error)")
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

        do {
            try await SupabaseAuthManager.hardSignOut(appRouter: appRouter)
            return true
        } catch {
            #if DEBUG
            print("退出登录失败: \(error)")
            #endif
            authErrorMessage = error.localizedDescription
            return false
        }
    }

    func softExitToLogin(appRouter: AppRouter) {
        SupabaseAuthManager.softExitToLogin(appRouter: appRouter)
    }

    func deleteAccount(appRouter: AppRouter) async -> Bool {
        guard isProcessingAuth == false else { return false }
        isProcessingAuth = true
        authErrorMessage = nil
        defer { isProcessingAuth = false }

        AuthSessionGuard.shared.beginLoggingOut()
        appRouter.logVIPAccessState(trigger: "用户退出前")
        defer { Task { await AuthSessionGuard.shared.endLoggingOut() } }
        do {
            // 预留：接入 delete-account Edge Function / RPC 后在此调用
            // try await supabase.functions.invoke("delete-account")
            await authService.cleanUpCurrentUserAvatars()
            try await SupabaseAuthManager.hardSignOut(appRouter: appRouter)
            return true
        } catch {
            #if DEBUG
            print("注销账号失败: \(error)")
            #endif
            authErrorMessage = error.localizedDescription
            return false
        }
    }

    private enum ActionType {
        case create
        case join
    }

    private enum Copy {
        static let networkError = L10n.Common.networkConnectionErrorPleaseCheckYourConne.string()
        static let createHouseholdFailed = L10n.Family.failedToCreateGroupPleaseTryAgainLater.string()
        static let joinHouseholdFailed = L10n.Family.couldNotJoinTheGroupPleaseTryAgainLater.string()
        static let emptyHouseholdName = L10n.Family.groupNameCannotBeEmptyPleaseEnterANameB.string()
        static let invalidInviteCode = L10n.Family.invalidInviteCodePleaseCheckAndTryAgain.string()
        static let sessionExpired = L10n.Auth.yourSignInSessionHasExpiredPleaseSignIn.string()
        static let forbidden = L10n.Common.youDonTHavePermissionToPerformThisAction.string()
        static let householdNotFound = L10n.Family.thisGroupDoesNotExistOrHasBeenDeletedPl.string()
        static let backendMigrationRequired = L10n.Common.backendUpgradeRequiredPleaseApplyTheLatest2.string()
        static let alreadyMember = L10n.Family.youAreAlreadyAMemberOfThisGroup.string()
        static let joinRequestPending = L10n.Common.yourJoinRequestHasBeenSubmittedPleaseWait.string()
        static let inviteCodeExpired = L10n.Family.thisInviteCodeHasExpiredPleaseAskTheCrea.string()
        static let inviteLinkUsed = L10n.Family.thisInviteLinkHasAlreadyBeenUsedPleaseAs.string()
        static let householdNameMismatch = L10n.Family.groupNameDoesNotMatchPleaseEnterItAgain.string()
        static let disbandUnauthorized = L10n.Family.onlyTheCreatorCanDisbandThisGroup.string()
        static let unknownError = L10n.Common.somethingWentWrongPleaseTryAgainLater.string()
    }

    private func mapErrorMessage(_ error: Error, action: ActionType) -> String {
        if let routingError = error as? HouseholdRoutingError {
            return mapHouseholdRoutingError(routingError)
        }

        switch action {
        case .create:
            #if DEBUG
            #if canImport(Supabase)
            if let dbError = error as? PostgrestError {
                print("创建群组失败 PostgrestError: \(dbError.message ?? dbError.localizedDescription)")
            } else {
                print("创建群组失败: \(error)")
            }
            #else
            print("创建群组失败: \(error)")
            #endif
            #endif
            return Copy.createHouseholdFailed
        case .join:
            #if DEBUG
            print("加入群组失败: \(error)")
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
            return L10n.Family.youAreTheCreatorOfThisGroupTransferOwner.string()
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
