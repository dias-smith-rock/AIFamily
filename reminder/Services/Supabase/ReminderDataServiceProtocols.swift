import Foundation

protocol TaskDataService {
    /// 拉取指定群组下的任务列表。可见行由 **Supabase RLS** 决定，客户端只按 `household_id` 约束即可。
    /// - Important: `involved_member_ids` 存的是 **`household_memberships.id`（成员身份 ID）**，不是 `auth.users` 的 user id。
    ///   禁止在 Query（如 `.filter` / `.or`）或二次 `.filter` 里用 `auth.uid()` / 当前 user id 去比对 `involvedMemberIds`。
    func fetchTasks(in householdId: UUID) async throws -> [FamilyTask]
    /// 通过 `create_task_with_spatial` 创建任务；`geofence` 优先于 `task.geofence`。
    func createTask(_ task: FamilyTask, geofence: TaskGeofence?) async throws -> FamilyTask
    func updateTask(_ task: FamilyTask) async throws -> FamilyTask
    /// 成员侧状态机：完成时走 `complete_task_with_spatial`；其余状态仍 PATCH `status`。
    func patchTaskStatus(
        taskId: UUID,
        to status: TaskStatus,
        completionLocation: TaskCompletionLocation?,
        actingMembershipId: UUID?
    ) async throws -> FamilyTask
    func deleteTask(taskId: UUID) async throws
}

extension TaskDataService {
    func createTask(_ task: FamilyTask) async throws -> FamilyTask {
        try await createTask(task, geofence: nil)
    }

    func patchTaskStatus(taskId: UUID, to status: TaskStatus) async throws -> FamilyTask {
        try await patchTaskStatus(
            taskId: taskId,
            to: status,
            completionLocation: nil,
            actingMembershipId: nil
        )
    }
}

protocol FeedbackDataService {
    func fetchFeedbacks(in householdId: UUID, for taskId: UUID?) async throws -> [Feedback]
    func createFeedback(_ feedback: Feedback) async throws -> Feedback
    func markFeedbackAsRead(id: UUID, readerId: UUID) async throws
    /// 插入系统消息（`sender_id` 为空）；`taskId` 可选，无任务时省略该列。
    func createSystemFeedback(householdId: UUID, content: String, taskId: UUID?) async throws -> Feedback
}

/// 双轨制群组名册：有账号成员（memberships + 全局 profile）与无账号虚拟成员（household 绑定 profile）。
struct HouseholdMemberRoster: Equatable {
    let profiles: [FamilyProfile]
    let memberships: [HouseholdMembership]

    /// 仅保留 `status == active` 的身份行；虚拟档案（无 membership）仍保留。
    func filteredToActiveMembers(in householdId: UUID) -> HouseholdMemberRoster {
        let activeMemberships = memberships.filter { $0.isActiveMembership() }
        let activeProfileIds = Set(activeMemberships.compactMap(\.profileId))
        let activeUserIds = Set(activeMemberships.compactMap(\.userId))
        let activeProfiles = profiles.filter { profile in
            if profile.isVirtualUser {
                return profile.householdId == householdId
            }
            if activeProfileIds.contains(profile.id) {
                return true
            }
            // membership.profile_id 为空时仍可能通过 user_id 关联到正式档案
            if let uid = profile.userId, activeUserIds.contains(uid) {
                return true
            }
            return false
        }
        return HouseholdMemberRoster(profiles: activeProfiles, memberships: activeMemberships)
    }
}

protocol HouseholdMembershipDataService {
    /// 并发拉取有账号成员（memberships 连表）与无账号虚拟成员（family_profiles 单表），合并为统一名册。
    /// - Parameter activeOnly: 为 `true` 时仅含 `household_memberships.status = active`（已退出等为 inactive/disabled 的不展示）。
    func fetchMemberRoster(in householdId: UUID, activeOnly: Bool) async throws -> HouseholdMemberRoster
    func fetchMemberships(in householdId: UUID) async throws -> [HouseholdMembership]
    func createMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership
    func updateMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership
    /// 按 `household_id` + `profile_id`（`family_profiles.id`）更新组织内昵称；虚拟成员无匹配行时不报错。
    func updateNickname(householdId: UUID, profileId: UUID, nickname: String) async throws
    /// 将真实成员移出群组：删除其在当前 `household_memberships` 中的身份行（不删除全局 `family_profiles`）。
    func removeMember(householdId: UUID, userId: UUID) async throws
}

protocol FamilyProfileDataService {
    func fetchProfiles(in householdId: UUID) async throws -> [FamilyProfile]
    /// 按 `family_profiles.id` 拉取单行（含嵌套 `household_memberships!profile_id`）。
    func fetchProfile(id: UUID) async throws -> FamilyProfile?
    func createLocalProfile(householdId: UUID, draft: LocalProfileDraft) async throws
    func updateProfile(profileId: UUID, draft: LocalProfileDraft) async throws
    /// 删除无账号虚拟成员档案（`family_profiles` 单行）。
    func deleteProfile(profileId: UUID) async throws
}

protocol LedgerDataService {
    func fetchCategories(in householdId: UUID, type: LedgerEntryType?, includeDeleted: Bool) async throws -> [ExpenseCategory]
    func fetchTags(in householdId: UUID, categoryId: UUID?, includeDeleted: Bool) async throws -> [CategoryTag]
    func fetchTransactions(in householdId: UUID) async throws -> [LedgerTransaction]
    func fetchTagMappings(for transactionIds: [UUID]) async throws -> [TransactionTagMapping]
    func createTransaction(_ draft: LedgerTransactionDraft) async throws -> LedgerTransaction
    func updateTransaction(id: UUID, draft: LedgerTransactionDraft) async throws -> LedgerTransaction
    func deleteTransaction(id: UUID) async throws
    func softDeleteCategory(id: UUID) async throws
    func softDeleteTag(id: UUID) async throws
    func createCategory(
        householdId: UUID,
        type: LedgerEntryType,
        name: String,
        icon: String,
        colorHex: String?
    ) async throws -> ExpenseCategory
    func updateCategory(
        id: UUID,
        name: String,
        icon: String,
        colorHex: String?
    ) async throws -> ExpenseCategory
    func createTag(householdId: UUID, categoryId: UUID, name: String) async throws -> CategoryTag
    /// 若组织缺少默认分类，幂等补齐（任意活跃成员可调用，含 member）。
    func ensurePresetCategories(in householdId: UUID) async throws
}
