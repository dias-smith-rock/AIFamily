import Foundation
import Combine

@MainActor
final class FamilyViewModel: ObservableObject {
    @Published private(set) var members: [FamilyMember] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let familyMemberService: FamilyMemberDataService

    init(familyMemberService: FamilyMemberDataService) {
        self.familyMemberService = familyMemberService
    }

    func loadMembers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            members = try await familyMemberService.fetchFamilyMembers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createMember(_ member: FamilyMember) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let createdMember = try await familyMemberService.createFamilyMember(member)
            members.append(createdMember)
            members.sort { $0.createdAt < $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
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
