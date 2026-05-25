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
    private var currentHouseholdId: UUID?

    init(
        feedbackService: FeedbackDataService,
        voiceStorageService: VoiceStorageService,
        feedbackRealtimeService: FeedbackRealtimeService
    ) {
        self.feedbackService = feedbackService
        self.voiceStorageService = voiceStorageService
        self.feedbackRealtimeService = feedbackRealtimeService
    }

    func setHouseholdContext(_ householdId: UUID?) {
        currentHouseholdId = householdId
    }

    func loadFeedbacks(taskId: UUID? = nil) async {
        guard let householdId = currentHouseholdId else {
            feedbacks = []
            errorMessage = "当前未选择群组。"
            hasLoadedOnce = true
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            feedbacks = try await feedbackService.fetchFeedbacks(in: householdId, for: taskId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createFeedback(_ feedback: Feedback) async {
        guard let householdId = currentHouseholdId else {
            errorMessage = "当前未选择群组。"
            return
        }
        guard feedback.householdId == nil || feedback.householdId == householdId else {
            errorMessage = "反馈写入失败：群组上下文不一致。"
            return
        }

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

    func markAsRead(_ id: UUID, readerId: UUID) async {
        errorMessage = nil
        do {
            try await feedbackService.markFeedbackAsRead(id: id, readerId: readerId)
            guard let index = feedbacks.firstIndex(where: { $0.id == id }) else { return }
            feedbacks[index] = feedbacks[index].markingRead(by: readerId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRealtime() async {
        guard isRealtimeSubscribed == false else { return }
        do {
            try await feedbackRealtimeService.subscribeToFeedbackInserts { [weak self] feedback in
                Task { @MainActor in
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

    func uploadVoiceFeedback(
        taskId: UUID,
        senderId: UUID,
        audioData: Data
    ) async {
        guard let householdId = currentHouseholdId else {
            errorMessage = "当前未选择群组。"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fileName = "\(taskId.uuidString)-\(UUID().uuidString).m4a"
            let storagePath = "feedbacks/\(fileName)"
            _ = try await voiceStorageService.uploadVoiceFeedback(data: audioData, fileName: fileName)
            let feedback = Feedback(
                id: UUID(),
                householdId: householdId,
                taskId: taskId,
                senderId: senderId,
                content: nil,
                voiceUrl: storagePath,
                imageUrls: nil,
                readBy: nil,
                isDeleted: false,
                replyToId: nil,
                createdAt: Date(),
                updatedAt: nil,
                mediaClearedAt: nil
            )
            let created = try await feedbackService.createFeedback(feedback)
            feedbacks.insert(created, at: 0)
            feedbacks.sort { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
