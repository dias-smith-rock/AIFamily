import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ReviewRedirectManager: ObservableObject {
    static let shared = ReviewRedirectManager()

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

    @Published var showReviewAlert = false

    let appStoreReviewURL = "https://apps.apple.com/app/idYOUR_APP_ID?action=write-review"

    func checkAndTriggerAlert(for milestone: Milestone) {
        guard shouldPrompt(for: milestone) else { return }
        markPrompted(for: milestone)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showReviewAlert = true
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

struct ReviewAlertModifier: ViewModifier {
    @ObservedObject var manager: ReviewRedirectManager

    func body(content: Content) -> some View {
        content
            .alert(
                L10n.Common.enjoyingWesync.localized,
                isPresented: $manager.showReviewAlert
            ) {
                Button(L10n.Common.maybeLater.localized, role: .cancel) {}
                Button(L10n.Common.writeAReview.localized) {
                    openReviewPage()
                }
            } message: {
                Text(L10n.Family.yourFeedbackHelpsUsImproveTheAppForGroup.localized)
            }
    }

    private func openReviewPage() {
        guard let url = URL(string: manager.appStoreReviewURL) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

extension View {
    func reviewAlertModifier(manager: ReviewRedirectManager) -> some View {
        modifier(ReviewAlertModifier(manager: manager))
    }
}
