import Foundation
import Combine

@MainActor
final class ViewModelFactory: ObservableObject {
    private let services: ReminderServiceContainer

    init(services: ReminderServiceContainer) {
        self.services = services
    }

    func makeScheduleViewModel() -> ScheduleViewModel {
        ScheduleViewModel(taskService: services.taskService)
    }

    func makeFeedbackFeedViewModel() -> FeedbackFeedViewModel {
        FeedbackFeedViewModel(feedbackService: services.feedbackService)
    }

    func makeFamilyViewModel() -> FamilyViewModel {
        FamilyViewModel(familyMemberService: services.familyMemberService)
    }
}

@MainActor
enum AppViewModels {
    private static var factory = ViewModelFactory(services: .mock())

    static func configure(with factory: ViewModelFactory) {
        self.factory = factory
    }

    static func makeScheduleViewModel() -> ScheduleViewModel {
        factory.makeScheduleViewModel()
    }

    static func makeFeedbackFeedViewModel() -> FeedbackFeedViewModel {
        factory.makeFeedbackFeedViewModel()
    }

    static func makeFamilyViewModel() -> FamilyViewModel {
        factory.makeFamilyViewModel()
    }
}

/*
 页面层用法（无需关心 Preview / Live）：
 @StateObject private var viewModel = AppViewModels.makeScheduleViewModel()
 */
