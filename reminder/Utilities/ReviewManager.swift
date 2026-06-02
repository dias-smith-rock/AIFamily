import SwiftUI
import Combine
import StoreKit

@MainActor
final class ReviewManager: ObservableObject {
    static let shared = ReviewManager()

    enum Milestone {
        case firstTask
        case virtualMember
        case taskAcceptance
        case firstCompletion
    }

    @AppStorage("hasPromptedForFirstTask") private var hasPromptedForFirstTask = false
    @AppStorage("hasPromptedForVirtualMember") private var hasPromptedForVirtualMember = false
    @AppStorage("hasPromptedForTaskAcceptance") private var hasPromptedForTaskAcceptance = false
    @AppStorage("hasPromptedForFirstCompletion") private var hasPromptedForFirstCompletion = false

    func triggerReview(for milestone: Milestone, requestReview: RequestReviewAction) {
        guard shouldPrompt(for: milestone) else { return }
        markPrompted(for: milestone)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            requestReview()
        }
    }

    private func shouldPrompt(for milestone: Milestone) -> Bool {
        switch milestone {
        case .firstTask:
            return hasPromptedForFirstTask == false
        case .virtualMember:
            return hasPromptedForVirtualMember == false
        case .taskAcceptance:
            return hasPromptedForTaskAcceptance == false
        case .firstCompletion:
            return hasPromptedForFirstCompletion == false
        }
    }

    private func markPrompted(for milestone: Milestone) {
        switch milestone {
        case .firstTask:
            hasPromptedForFirstTask = true
        case .virtualMember:
            hasPromptedForVirtualMember = true
        case .taskAcceptance:
            hasPromptedForTaskAcceptance = true
        case .firstCompletion:
            hasPromptedForFirstCompletion = true
        }
    }
}
