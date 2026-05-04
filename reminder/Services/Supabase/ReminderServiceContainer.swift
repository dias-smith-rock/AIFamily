import Foundation

struct ReminderServiceContainer {
    let taskService: TaskDataService
    let feedbackService: FeedbackDataService
    let membershipService: HouseholdMembershipDataService
    let authService: AuthService
    let voiceStorageService: VoiceStorageService
    let feedbackRealtimeService: FeedbackRealtimeService
    let inviteLinkService: InviteLinkService
    let householdRoutingService: HouseholdRoutingService

    static func live() -> ReminderServiceContainer {
        let provider = SupabaseProvider()
        return ReminderServiceContainer(
            taskService: SupabaseTaskDataService(provider: provider),
            feedbackService: SupabaseFeedbackDataService(provider: provider),
            membershipService: SupabaseHouseholdMembershipDataService(provider: provider),
            authService: SupabaseAuthService(provider: provider),
            voiceStorageService: SupabaseVoiceStorageService(provider: provider),
            feedbackRealtimeService: SupabaseFeedbackRealtimeService(provider: provider),
            inviteLinkService: SupabaseInviteLinkService(),
            householdRoutingService: SupabaseHouseholdRoutingService(provider: provider)
        )
    }

    static func mock() -> ReminderServiceContainer {
        ReminderServiceContainer(
            taskService: MockTaskDataService(),
            feedbackService: MockFeedbackDataService(),
            membershipService: MockHouseholdMembershipDataService(),
            authService: MockAuthService(),
            voiceStorageService: MockVoiceStorageService(),
            feedbackRealtimeService: MockFeedbackRealtimeService(),
            inviteLinkService: MockInviteLinkService(),
            householdRoutingService: MockHouseholdRoutingService()
        )
    }
}
