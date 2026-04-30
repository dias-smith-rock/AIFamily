import Foundation
import Combine

@MainActor
final class FeedbackFeedViewModel: ObservableObject {
    @Published private(set) var feedbacks: [Feedback] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoadedOnce = false

    private let feedbackService: FeedbackDataService
    private let voiceStorageService: VoiceStorageService
    private let feedbackRealtimeService: FeedbackRealtimeService
    private var isRealtimeSubscribed = false

    init(
        feedbackService: FeedbackDataService,
        voiceStorageService: VoiceStorageService,
        feedbackRealtimeService: FeedbackRealtimeService
    ) {
        self.feedbackService = feedbackService
        self.voiceStorageService = voiceStorageService
        self.feedbackRealtimeService = feedbackRealtimeService
    }

    func loadFeedbacks(taskId: UUID? = nil) async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

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

    func startRealtime() async {
        guard isRealtimeSubscribed == false else { return }
        do {
            try await feedbackRealtimeService.subscribeToFeedbackInserts { [weak self] feedback in
                _Concurrency.Task { @MainActor in
                    guard let self else { return }
                    if self.feedbacks.contains(where: { $0.id == feedback.id }) == false {
                        self.feedbacks.insert(feedback, at: 0)
                    }
                }
            }
            isRealtimeSubscribed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRealtime() async {
        await feedbackRealtimeService.unsubscribe()
        isRealtimeSubscribed = false
    }

    func uploadVoiceFeedback(taskId: UUID, senderId: UUID, audioData: Data, duration: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fileName = "\(taskId.uuidString)-\(UUID().uuidString).m4a"
            let audioURL = try await voiceStorageService.uploadVoiceFeedback(data: audioData, fileName: fileName)
            let feedback = Feedback(
                id: UUID(),
                taskId: taskId,
                senderId: senderId,
                type: .voice,
                text: nil,
                audioURL: audioURL,
                audioDurationSeconds: duration,
                isRead: false,
                createdAt: Date()
            )
            _ = try await feedbackService.createFeedback(feedback)
            feedbacks.insert(feedback, at: 0)
            feedbacks.sort { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
