import Foundation
import Combine

@MainActor
final class FeedbackFeedViewModel: ObservableObject {
    @Published private(set) var feedbacks: [Feedback] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let feedbackService: FeedbackDataService

    init(feedbackService: FeedbackDataService) {
        self.feedbackService = feedbackService
    }

    func loadFeedbacks(taskId: UUID? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            feedbacks = try await feedbackService.fetchFeedbacks(for: taskId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createFeedback(_ feedback: Feedback) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let createdFeedback = try await feedbackService.createFeedback(feedback)
            feedbacks.insert(createdFeedback, at: 0)
            feedbacks.sort { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markAsRead(_ id: UUID) async {
        errorMessage = nil
        do {
            try await feedbackService.markFeedbackAsRead(id: id)
            guard let index = feedbacks.firstIndex(where: { $0.id == id }) else { return }
            feedbacks[index].isRead = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
