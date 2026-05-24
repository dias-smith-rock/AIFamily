import Foundation
import Combine

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

    func fetchMyHouseholds() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await householdRoutingService.fetchMyJoinedHouseholds()
            joinedHouseholds = response.filter { household in
                household.isSelectable
                    && household.household?.isArchivedOrDeleted == false
            }
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
            return try await householdRoutingService.createHousehold(displayName: displayName)
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
        } catch {
            errorMessage = mapErrorMessage(error, action: .join)
            return false
        }
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

    private func mapErrorMessage(_ error: Error, action: ActionType) -> String {
        if let routingError = error as? HouseholdRoutingError {
            switch routingError {
            case .invalidHouseholdName:
                return "家庭名称不能为空，请输入后再创建。"
            case .householdNameTaken:
                return "创建家庭失败，请稍后重试。"
            case .invalidInviteCode:
                return "邀请码格式不正确或不存在，请检查后重试。"
            case .unauthenticated:
                return "当前登录状态已失效，请重新登录后再试。"
            case .forbidden:
                return "你没有权限执行该操作。"
            case .householdNotFound:
                return "家庭不存在或已被删除，请刷新后重试。"
            case .backendMigrationRequired:
                return "后端尚未完成升级，请先执行最新 Supabase migration 后重试。"
            case .alreadyActiveMember:
                return "你已经是该家庭成员，无需重复加入。"
            case .joinRequestPending:
                return "你的加入申请已提交，请等待管理员审批。"
            case .nonceExpired:
                return "邀请链接已过期，请向管理员重新获取。"
            case .nonceConsumed:
                return "邀请链接已被使用，请向管理员重新获取。"
            case .networkFailure:
                return "网络或服务异常，请稍后再试。"
            case .householdNameMismatch:
                return "家庭名称不匹配，请重新输入。"
            case .disbandUnauthorized:
                return "只有家庭创建者才能解散该家庭。"
            case .unknown:
                return "发生未知错误，请稍后重试。"
            }
        }

        switch action {
        case .create:
            #if DEBUG
            print("创建家庭失败: \(error)")
            #endif
            return "创建家庭失败，请稍后重试。"
        case .join:
            #if DEBUG
            return error.localizedDescription
            #else
            return "加入家庭失败，请稍后重试。"
            #endif
        }
    }
}
