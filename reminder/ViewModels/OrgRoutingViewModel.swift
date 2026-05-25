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

    func createHousehold(displayName: String) async -> UUID? {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            let householdId = try await householdRoutingService.createHousehold(displayName: displayName)
            await CreatorRoleSnapshotStore.markKnownCreatorHouseholdIfPossible(householdId)
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

    func acknowledgeError() {
        errorMessage = nil
    }

    func signOut(appRouter: AppRouter) async -> Bool {
        guard isProcessingAuth == false else { return false }
        isProcessingAuth = true
        authErrorMessage = nil
        defer { isProcessingAuth = false }

        do {
            try await authService.signOut()
            await appRouter.refreshStateFromBackend()
            return true
        } catch {
            #if DEBUG
            print("退出登录失败: \(error)")
            #endif
            authErrorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAccount(appRouter: AppRouter) async -> Bool {
        guard isProcessingAuth == false else { return false }
        isProcessingAuth = true
        authErrorMessage = nil
        defer { isProcessingAuth = false }

        do {
            // 预留：接入 delete-account Edge Function / RPC 后在此调用
            // try await supabase.functions.invoke("delete-account")
            await authService.cleanUpCurrentUserAvatars()
            try await authService.signOut()
            await appRouter.refreshStateFromBackend()
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
        static let networkError = String(localized: "Network connection error. Please check your connection and try again.")
        static let createHouseholdFailed = String(localized: "Failed to create household. Please try again later.")
        static let joinHouseholdFailed = String(localized: "Could not join the household. Please try again later or contact the creator.")
        static let emptyHouseholdName = String(localized: "Household name cannot be empty. Please enter a name before creating.")
        static let invalidInviteCode = String(localized: "Invalid invite code. Please check and try again.")
        static let sessionExpired = String(localized: "Your sign-in session has expired. Please sign in again.")
        static let forbidden = String(localized: "You don't have permission to perform this action.")
        static let householdNotFound = String(localized: "This household does not exist or has been deleted. Please refresh and try again.")
        static let backendMigrationRequired = String(localized: "Backend upgrade required. Please apply the latest Supabase migration and try again.")
        static let alreadyMember = String(localized: "You are already a member of this household.")
        static let joinRequestPending = String(localized: "Your join request has been submitted. Please wait for admin approval.")
        static let inviteCodeExpired = String(localized: "This invite code has expired. Please ask the creator to share a new one.")
        static let inviteLinkUsed = String(localized: "This invite link has already been used. Please ask the admin for a new one.")
        static let householdNameMismatch = String(localized: "Household name does not match. Please enter it again.")
        static let disbandUnauthorized = String(localized: "Only the creator can disband this household.")
        static let unknownError = String(localized: "Something went wrong. Please try again later.")
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
