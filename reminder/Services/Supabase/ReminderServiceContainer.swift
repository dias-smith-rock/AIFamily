import Foundation

struct ReminderServiceContainer {
    let taskService: TaskDataService
    let feedbackService: FeedbackDataService
    let familyMemberService: FamilyMemberDataService

    static func live() -> ReminderServiceContainer {
        let provider = SupabaseProvider()
        return ReminderServiceContainer(
            taskService: SupabaseTaskDataService(provider: provider),
            feedbackService: SupabaseFeedbackDataService(provider: provider),
            familyMemberService: SupabaseFamilyMemberDataService(provider: provider)
        )
    }

    static func mock() -> ReminderServiceContainer {
        ReminderServiceContainer(
            taskService: MockTaskDataService(),
            feedbackService: MockFeedbackDataService(),
            familyMemberService: MockFamilyMemberDataService()
        )
    }
}
