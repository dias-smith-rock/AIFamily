import Foundation

struct ReminderServiceContainer {
    let taskService: TaskDataService
    let feedbackService: FeedbackDataService
    let membershipService: HouseholdMembershipDataService
    let familyProfileService: FamilyProfileDataService
    let ledgerService: LedgerDataService
    let authService: AuthService
    let voiceStorageService: VoiceStorageService
    let avatarStorageService: AvatarStorageService
    let feedbackRealtimeService: FeedbackRealtimeService
    let inviteLinkService: InviteLinkService
    let householdRoutingService: HouseholdRoutingService
    let locationStateService: LocationStateDataService
    let locationTrailService: LocationTrailDataService

    static func live() -> ReminderServiceContainer {
        let provider = SupabaseProvider()
        let voiceStorageService = SupabaseVoiceStorageService(provider: provider)
        let avatarStorageService = SupabaseAvatarStorageService(provider: provider)
        return ReminderServiceContainer(
            taskService: SupabaseTaskDataService(provider: provider),
            feedbackService: SupabaseFeedbackDataService(provider: provider),
            membershipService: SupabaseHouseholdMembershipDataService(provider: provider),
            familyProfileService: SupabaseFamilyProfileDataService(provider: provider),
            ledgerService: SupabaseLedgerDataService(provider: provider),
            authService: SupabaseAuthService(
                provider: provider,
                avatarStorageService: avatarStorageService
            ),
            voiceStorageService: voiceStorageService,
            avatarStorageService: avatarStorageService,
            feedbackRealtimeService: SupabaseFeedbackRealtimeService(provider: provider),
            inviteLinkService: SupabaseInviteLinkService(),
            householdRoutingService: SupabaseHouseholdRoutingService(
                provider: provider,
                voiceStorageService: voiceStorageService
            ),
            locationStateService: SupabaseLocationStateDataService(provider: provider),
            locationTrailService: SupabaseLocationTrailDataService(provider: provider)
        )
    }

    static func mock() -> ReminderServiceContainer {
        ReminderServiceContainer(
            taskService: MockTaskDataService(),
            feedbackService: MockFeedbackDataService(),
            membershipService: MockHouseholdMembershipDataService(),
            familyProfileService: MockFamilyProfileDataService(),
            ledgerService: MockLedgerDataService(),
            authService: MockAuthService(),
            voiceStorageService: MockVoiceStorageService(),
            avatarStorageService: MockAvatarStorageService(),
            feedbackRealtimeService: MockFeedbackRealtimeService(),
            inviteLinkService: MockInviteLinkService(),
            householdRoutingService: MockHouseholdRoutingService(),
            locationStateService: MockLocationStateDataService(),
            locationTrailService: MockLocationTrailDataService()
        )
    }
}
