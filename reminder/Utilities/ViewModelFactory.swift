import Foundation
import Combine

@MainActor
final class ViewModelFactory: ObservableObject {
    private let services: ReminderServiceContainer

    init(services: ReminderServiceContainer) {
        self.services = services
    }

    func makeScheduleViewModel() -> ScheduleViewModel {
        ScheduleViewModel(
            taskService: services.taskService,
            membershipService: services.membershipService,
            familyProfileService: services.familyProfileService
        )
    }

    func makeTodoListViewModel() -> TodoListViewModel {
        TodoListViewModel(
            taskService: services.taskService,
            membershipService: services.membershipService,
            familyProfileService: services.familyProfileService
        )
    }

    func makeLedgerViewModel() -> FamilyLedgerViewModel {
        FamilyLedgerViewModel(
            ledgerService: services.ledgerService,
            membershipService: services.membershipService,
            familyProfileService: services.familyProfileService
        )
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
            profileService: services.familyProfileService,
            membershipService: services.membershipService,
            taskService: services.taskService,
            avatarStorageService: services.avatarStorageService,
            inviteLinkService: services.inviteLinkService,
            authService: services.authService,
            householdRoutingService: services.householdRoutingService
        )
    }

    func makeTransferOwnershipViewModel(from familyViewModel: FamilyViewModel) -> TransferOwnershipViewModel {
        TransferOwnershipViewModel(
            householdId: familyViewModel.transferHouseholdId ?? UUID(),
            currentUserId: familyViewModel.currentAuthUserId ?? UUID(),
            members: familyViewModel.transferMembersSnapshot,
            profiles: familyViewModel.transferProfilesSnapshot,
            householdRoutingService: services.householdRoutingService,
            feedbackService: services.feedbackService,
            taskService: services.taskService
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
        OrgRoutingViewModel(
            householdRoutingService: services.householdRoutingService,
            authService: services.authService
        )
    }

    func makeMineViewModel() -> MineViewModel {
        MineViewModel(authService: services.authService)
    }

    func makeVIPSubscriptionViewModel() -> VIPSubscriptionViewModel {
        VIPSubscriptionViewModel()
    }

    func makeLocationMainViewModel() -> LocationMainViewModel {
        LocationMainViewModel(
            locationStateService: services.locationStateService,
            membershipService: services.membershipService,
            previewMembers: nil
        )
    }

    func makeLiveLocationManager() -> LiveLocationManager {
        LiveLocationManager(locationStateService: services.locationStateService)
    }

    func makeScheduleSearchViewModel() -> ScheduleSearchViewModel {
        ScheduleSearchViewModel(
            taskService: services.taskService,
            ledgerService: services.ledgerService,
            membershipService: services.membershipService
        )
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

    static func makeTodoListViewModel() -> TodoListViewModel {
        factory.makeTodoListViewModel()
    }

    static func makeLedgerViewModel() -> FamilyLedgerViewModel {
        factory.makeLedgerViewModel()
    }

    static func makeFeedbackFeedViewModel() -> FeedbackFeedViewModel {
        factory.makeFeedbackFeedViewModel()
    }

    static func makeFamilyViewModel() -> FamilyViewModel {
        factory.makeFamilyViewModel()
    }

    static func makeTransferOwnershipViewModel(from familyViewModel: FamilyViewModel) -> TransferOwnershipViewModel {
        factory.makeTransferOwnershipViewModel(from: familyViewModel)
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

    static func makeMineViewModel() -> MineViewModel {
        factory.makeMineViewModel()
    }

    static func makeVIPSubscriptionViewModel() -> VIPSubscriptionViewModel {
        factory.makeVIPSubscriptionViewModel()
    }

    static func makeLocationMainViewModel() -> LocationMainViewModel {
        factory.makeLocationMainViewModel()
    }

    static func makeLiveLocationManager() -> LiveLocationManager {
        factory.makeLiveLocationManager()
    }

    static func makeScheduleSearchViewModel() -> ScheduleSearchViewModel {
        factory.makeScheduleSearchViewModel()
    }
}

/*
 页面层用法（无需关心 Preview / Live）：
 @StateObject private var viewModel = AppViewModels.makeScheduleViewModel()
 */
