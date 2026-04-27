import Foundation

protocol TaskDataService {
    func fetchTasks() async throws -> [Task]
    func createTask(_ task: Task) async throws -> Task
    func updateTask(_ task: Task) async throws -> Task
}

protocol FeedbackDataService {
    func fetchFeedbacks(for taskId: UUID?) async throws -> [Feedback]
    func createFeedback(_ feedback: Feedback) async throws -> Feedback
    func markFeedbackAsRead(id: UUID) async throws
}

protocol FamilyMemberDataService {
    func fetchFamilyMembers() async throws -> [FamilyMember]
    func createFamilyMember(_ member: FamilyMember) async throws -> FamilyMember
    func updateFamilyMember(_ member: FamilyMember) async throws -> FamilyMember
}
