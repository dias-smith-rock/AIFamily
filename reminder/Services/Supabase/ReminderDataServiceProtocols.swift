import Foundation

protocol TaskDataService {
    func fetchTasks(in householdId: UUID) async throws -> [FamilyTask]
    func createTask(_ task: FamilyTask) async throws -> FamilyTask
    func updateTask(_ task: FamilyTask) async throws -> FamilyTask
    /// 仅更新 `status` 列并返回最新行，用于成员侧状态机操作。
    func patchTaskStatus(taskId: UUID, to status: TaskStatus) async throws -> FamilyTask
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
