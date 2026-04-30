import Foundation
import Combine

@MainActor
final class FamilyViewModel: ObservableObject {
    @Published private(set) var members: [FamilyMember] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var requiresLogin = false

    private let familyMemberService: FamilyMemberDataService
    private let inviteLinkService: InviteLinkService
    private let authService: AuthService

    init(
        familyMemberService: FamilyMemberDataService,
        inviteLinkService: InviteLinkService,
        authService: AuthService
    ) {
        self.familyMemberService = familyMemberService
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
            members = try await familyMemberService.fetchFamilyMembers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func didLoginSuccessfully() async {
        requiresLogin = false
        await loadMembers()
    }

    @discardableResult
    func createMember(_ member: FamilyMember) async -> FamilyMember? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let createdMember = try await familyMemberService.createFamilyMember(member)
            members.append(createdMember)
            members.sort { $0.createdAt < $1.createdAt }
            return createdMember
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func generateSignedInviteLink(for member: FamilyMember) async -> URL? {
        let token = member.inviteToken ?? "invite-\(member.id.uuidString.lowercased())"
        do {
            return try await inviteLinkService.generateSignedInviteLink(
                token: token,
                channel: member.notificationChannel,
                expiresInSeconds: 900
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateMember(_ member: FamilyMember) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let updatedMember = try await familyMemberService.updateFamilyMember(member)
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
