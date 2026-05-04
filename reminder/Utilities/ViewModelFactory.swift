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
        FeedbackFeedViewModel(
            feedbackService: services.feedbackService,
            voiceStorageService: services.voiceStorageService,
            feedbackRealtimeService: services.feedbackRealtimeService
        )
    }

    func makeFamilyViewModel() -> FamilyViewModel {
        FamilyViewModel(
            membershipService: services.membershipService,
            inviteLinkService: services.inviteLinkService,
            authService: services.authService
        )
    }

    func makeAssistantViewModel() -> AssistantViewModel {
        AssistantViewModel(
            taskService: services.taskService,
            parser: RuleBasedAIParserService()
        )
    }

    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(authService: services.authService)
    }

    func makeOrgRoutingViewModel() -> OrgRoutingViewModel {
        OrgRoutingViewModel(householdRoutingService: services.householdRoutingService)
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

    static func makeAssistantViewModel() -> AssistantViewModel {
        factory.makeAssistantViewModel()
    }

    static func makeAuthViewModel() -> AuthViewModel {
        factory.makeAuthViewModel()
    }

    static func makeOrgRoutingViewModel() -> OrgRoutingViewModel {
        factory.makeOrgRoutingViewModel()
    }
}

/*
 页面层用法（无需关心 Preview / Live）：
 @StateObject private var viewModel = AppViewModels.makeScheduleViewModel()
 */
