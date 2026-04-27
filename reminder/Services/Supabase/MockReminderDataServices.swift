import Foundation

actor MockTaskDataService: TaskDataService {
    private var tasks: [Task] = Task.mockTasks

    func fetchTasks() async throws -> [Task] {
        tasks.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func createTask(_ task: Task) async throws -> Task {
        tasks.append(task)
        return task
    }

    func updateTask(_ task: Task) async throws -> Task {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            throw SupabaseServiceError.invalidResponse
        }
        tasks[index] = task
        return task
    }
}

actor MockFeedbackDataService: FeedbackDataService {
    private var feedbacks: [Feedback] = Feedback.mockFeedbacks

    func fetchFeedbacks(for taskId: UUID?) async throws -> [Feedback] {
        let filtered = taskId.map { id in
            feedbacks.filter { $0.taskId == id }
        } ?? feedbacks

        return filtered.sorted { $0.createdAt > $1.createdAt }
    }

    func createFeedback(_ feedback: Feedback) async throws -> Feedback {
        feedbacks.append(feedback)
        return feedback
    }

    func markFeedbackAsRead(id: UUID) async throws {
        guard let index = feedbacks.firstIndex(where: { $0.id == id }) else {
            throw SupabaseServiceError.invalidResponse
        }
        feedbacks[index].isRead = true
    }
}

actor MockFamilyMemberDataService: FamilyMemberDataService {
    private var members: [FamilyMember] = FamilyMember.mockMembers

    func fetchFamilyMembers() async throws -> [FamilyMember] {
        members.sorted { $0.createdAt < $1.createdAt }
    }

    func createFamilyMember(_ member: FamilyMember) async throws -> FamilyMember {
        members.append(member)
        return member
    }

    func updateFamilyMember(_ member: FamilyMember) async throws -> FamilyMember {
        guard let index = members.firstIndex(where: { $0.id == member.id }) else {
            throw SupabaseServiceError.invalidResponse
        }
        members[index] = member
        return member
    }
}
