import SwiftUI

// MARK: - Feedback

extension L10n {
    enum Feedback {
    static let feedback = Entry(key: "feedback_feedback", table: .feedback)
    static let feedbackLegal = Entry(key: "feedback_feedback_legal", table: .feedback)
    static let filterAll = Entry(key: "feedback_filter_all", table: .feedback)
    static let filterUnread = Entry(key: "feedback_filter_unread", table: .feedback)
    static let loadingFeedback = Entry(key: "feedback_loading_feedback", table: .feedback)
    static let locationNotSet = Entry(key: "feedback_location_not_set", table: .feedback)
    static let noFilteredMessages = Entry(key: "feedback_no_filtered_messages", table: .feedback)
    static let noMessagesYet = Entry(key: "feedback_no_messages_yet", table: .feedback)
    static let systemMessage = Entry(key: "feedback_system_message", table: .feedback)
    static let trySwitchToAllFilter = Entry(key: "feedback_try_switch_to_all_filter", table: .feedback)
    static let unreadOnly = Entry(key: "feedback_unread_only", table: .feedback)
    static let viewAllMessages = Entry(key: "feedback_view_all_messages", table: .feedback)
    static let voiceMessagesAppearHere = Entry(key: "feedback_voice_messages_appear_here", table: .feedback)
    }
}
