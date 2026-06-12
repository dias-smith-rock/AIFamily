import Foundation
import Combine

@MainActor
final class TransferOwnershipViewModel: ObservableObject {
    @Published var isTransferring = false
    @Published var transferError: String?
    @Published var selectedMember: FamilyMember?
    @Published private(set) var didTransferSuccessfully = false

    private let householdId: UUID
    private let currentUserId: UUID
    private let householdRoutingService: HouseholdRoutingService
    private let feedbackService: FeedbackDataService
    private let taskService: TaskDataService
    private var members: [HouseholdMembership]
    private var profiles: [FamilyProfile]

    init(
        householdId: UUID,
        currentUserId: UUID,
        members: [HouseholdMembership],
        profiles: [FamilyProfile],
        householdRoutingService: HouseholdRoutingService,
        feedbackService: FeedbackDataService,
        taskService: TaskDataService
    ) {
        self.householdId = householdId
        self.currentUserId = currentUserId
        self.members = members
        self.profiles = profiles
        self.householdRoutingService = householdRoutingService
        self.feedbackService = feedbackService
        self.taskService = taskService
    }

    var eligibleMembers: [FamilyMember] {
        members.compactMap { membership in
            guard membership.isActiveMembership() else { return nil }
            guard let userId = membership.userId else { return nil }
            guard userId != currentUserId else { return nil }
            let profile = profile(for: membership)
            return FamilyMember.from(membership: membership, profile: profile)
        }
        .sorted { $0.nickname.localizedStandardCompare($1.nickname) == .orderedAscending }
    }

    func confirmTransfer(to targetUserId: UUID, targetDisplayName: String) async -> Bool {
        guard isTransferring == false else { return false }
        isTransferring = true
        transferError = nil
        defer { isTransferring = false }

        do {
            try await householdRoutingService.transferOwnership(
                householdId: householdId,
                newCreatorUserId: targetUserId
            )

            let systemMessage = AppLocalized.localized(
                L10n.Common.creatorPermissionsHaveBeenTransferredTo.formatted(targetDisplayName)
            )
            let anchorTaskId = await resolveSystemMessageTaskId()
            do {
                _ = try await feedbackService.createSystemFeedback(
                    householdId: householdId,
                    content: systemMessage,
                    taskId: anchorTaskId
                )
            } catch {
                #if DEBUG
                print("⚠️ 权限转移成功，但系统消息写入失败: \(error)")
                #endif
            }

            didTransferSuccessfully = true
            return true
        } catch {
            transferError = mapTransferError(error)
            return false
        }
    }

    private func profile(for membership: HouseholdMembership) -> FamilyProfile? {
        if let profileId = membership.profileId {
            if let match = profiles.first(where: { $0.id == profileId }) {
                return match
            }
        }
        if let userId = membership.userId {
            return profiles.first(where: { $0.userId == userId && $0.householdId == membership.householdId })
        }
        return nil
    }

    private func resolveSystemMessageTaskId() async -> UUID? {
        do {
            let tasks = try await taskService.fetchTasks(in: householdId)
            return tasks.first?.id
        } catch {
            return nil
        }
    }

    private func mapTransferError(_ error: Error) -> String {
        if let routingError = error as? HouseholdRoutingError {
            switch routingError {
            case .transferUnauthorized, .disbandUnauthorized, .forbidden:
                return AppLocalized.localized(L10n.Family.onlyTheCurrentGroupCreatorCanTransferOwne)
            case .transferInvalidTarget:
                return AppLocalized.localized(L10n.Family.theSelectedMemberCannotReceiveOwnershipPle)
            case .unauthenticated:
                return AppLocalized.localized(L10n.Auth.yourSignInSessionExpiredPleaseSignInAgai)
            case .householdNotFound:
                return AppLocalized.localized(L10n.Family.thisGroupDoesNotExistOrHasBeenDeletedPl)
            case .backendMigrationRequired:
                return AppLocalized.localized(L10n.Common.backendUpgradeRequiredPleaseApplyTheLatest)
            default:
                return AppLocalized.localized(L10n.Common.failedToTransferOwnershipPleaseTryAgainLa)
            }
        }
        #if DEBUG
        return error.localizedDescription
        #else
        return AppLocalized.localized(L10n.Common.failedToTransferOwnershipPleaseTryAgainLa)
        #endif
    }
}
