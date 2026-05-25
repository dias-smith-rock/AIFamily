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

            let systemMessage = "创建者权限已转移给「\(targetDisplayName)」。"
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
                return "只有当前群组的创建者才能转移权限。"
            case .transferInvalidTarget:
                return "所选成员不符合接收权限的条件，请重新选择。"
            case .unauthenticated:
                return "登录状态已失效，请重新登录后再试。"
            case .householdNotFound:
                return "群组不存在或已被删除，请刷新后重试。"
            case .backendMigrationRequired:
                return "后端尚未完成升级，请先执行最新 Supabase migration 后重试。"
            default:
                return "权限转移失败，请稍后重试。"
            }
        }
        #if DEBUG
        return error.localizedDescription
        #else
        return "权限转移失败，请稍后重试。"
        #endif
    }
}
