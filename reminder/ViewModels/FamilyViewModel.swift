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

    init(
        membershipService: HouseholdMembershipDataService,
        inviteLinkService: InviteLinkService,
        authService: AuthService
    ) {
        self.membershipService = membershipService
        self.inviteLinkService = inviteLinkService
        self.authService = authService
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

        requiresLogin = false
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            members = try await membershipService.fetchMemberships()
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
}
