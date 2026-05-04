import Foundation
import Combine

@MainActor
final class FamilyViewModel: ObservableObject {
    @Published private(set) var members: [HouseholdMembership] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var requiresLogin = false

    private let membershipService: HouseholdMembershipDataService
    private let inviteLinkService: InviteLinkService
    private let authService: AuthService
    private let householdRoutingService: HouseholdRoutingService
    private var currentHouseholdId: UUID?

    init(
        membershipService: HouseholdMembershipDataService,
        inviteLinkService: InviteLinkService,
        authService: AuthService,
        householdRoutingService: HouseholdRoutingService
    ) {
        self.membershipService = membershipService
        self.inviteLinkService = inviteLinkService
        self.authService = authService
        self.householdRoutingService = householdRoutingService
    }

    func setHouseholdContext(_ householdId: UUID?) {
        currentHouseholdId = householdId
    }

    func loadMembers() async {
        let hasSession = await authService.hasValidSession()
        guard hasSession else {
            requiresLogin = true
            errorMessage = nil
            members = []
            hasLoadedOnce = true
            return
        }

        guard let householdId = currentHouseholdId else {
            requiresLogin = false
            errorMessage = "当前未选择家庭。"
            members = []
            hasLoadedOnce = true
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
            members = try await membershipService.fetchMemberships(in: householdId)
        } catch {
            errorMessage = error.localizedDescription
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

    @discardableResult
    func renameHousehold(householdId: UUID, newName: String) async -> Bool {
        let normalizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            errorMessage = "家庭名称不能为空。"
            return false
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await householdRoutingService.renameHousehold(
                householdId: householdId,
                newName: normalizedName
            )
            return true
        } catch let error as HouseholdRoutingError {
            errorMessage = mapHouseholdRenameError(error)
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
