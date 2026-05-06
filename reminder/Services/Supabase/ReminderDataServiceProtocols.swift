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
}

protocol HouseholdMembershipDataService {
    func fetchMemberships(in householdId: UUID) async throws -> [HouseholdMembership]
    func createMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership
    func updateMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership
}
