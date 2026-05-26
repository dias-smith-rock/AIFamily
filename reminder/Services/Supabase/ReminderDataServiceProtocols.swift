import Foundation

protocol TaskDataService {
    /// 拉取指定家庭下的任务列表。可见行由 **Supabase RLS** 决定，客户端只按 `household_id` 约束即可。
    /// - Important: `involved_member_ids` 存的是 **`household_memberships.id`（成员身份 ID）**，不是 `auth.users` 的 user id。
    ///   禁止在 Query（如 `.filter` / `.or`）或二次 `.filter` 里用 `auth.uid()` / 当前 user id 去比对 `involvedMemberIds`。
    func fetchTasks(in householdId: UUID) async throws -> [FamilyTask]
    func createTask(_ task: FamilyTask) async throws -> FamilyTask
    func updateTask(_ task: FamilyTask) async throws -> FamilyTask
    /// 仅更新 `status` 列并返回最新行，用于成员侧状态机操作。
    func patchTaskStatus(taskId: UUID, to status: TaskStatus) async throws -> FamilyTask
    func deleteTask(taskId: UUID) async throws
}

protocol FeedbackDataService {
    func fetchFeedbacks(in householdId: UUID, for taskId: UUID?) async throws -> [Feedback]
    func createFeedback(_ feedback: Feedback) async throws -> Feedback
    func markFeedbackAsRead(id: UUID, readerId: UUID) async throws
    /// 插入系统消息（`sender_id` 为空）；`taskId` 可选，无任务时省略该列。
    func createSystemFeedback(householdId: UUID, content: String, taskId: UUID?) async throws -> Feedback
}

/// 以 `household_memberships` 为主表、嵌套 `family_profiles!profile_id` 的群组名册快照。
struct HouseholdMemberRoster: Equatable {
    let profiles: [FamilyProfile]
    let memberships: [HouseholdMembership]
}

protocol HouseholdMembershipDataService {
    /// 从关系表连表拉取成员与档案（**禁止**再按 `family_profiles.household_id` 过滤全局档案）。
    func fetchMemberRoster(in householdId: UUID) async throws -> HouseholdMemberRoster
    func fetchMemberships(in householdId: UUID) async throws -> [HouseholdMembership]
    func createMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership
    func updateMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership
    /// 按 `household_id` + `profile_id`（`family_profiles.id`）更新组织内昵称；虚拟成员无匹配行时不报错。
    func updateNickname(householdId: UUID, profileId: UUID, nickname: String) async throws
}

protocol FamilyProfileDataService {
    func fetchProfiles(in householdId: UUID) async throws -> [FamilyProfile]
    /// 按 `family_profiles.id` 拉取单行（含嵌套 `household_memberships!profile_id`）。
    func fetchProfile(id: UUID) async throws -> FamilyProfile?
    func createLocalProfile(householdId: UUID, draft: LocalProfileDraft) async throws
    func updateProfile(profileId: UUID, draft: LocalProfileDraft) async throws
}
