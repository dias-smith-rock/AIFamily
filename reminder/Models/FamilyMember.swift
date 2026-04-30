import Foundation

struct FamilyMember: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var role: FamilyRole
    var permission: MemberPermission
    var notificationChannel: NotificationChannel
    var phoneNumber: String?
    var avatarEmoji: String?
    var notificationsEnabled: Bool
    var inviteToken: String?
    var bindingStatus: BindingStatus
    var createdAt: Date
    var updatedAt: Date

    enum FamilyRole: String, Codable {
        case father
        case mother
        case grandparent
        case caregiver
        case child
    }

    enum MemberPermission: String, Codable {
        case owner
        case manager
        case executor
        case viewer
    }

    enum NotificationChannel: String, Codable {
        case app
        case wechat
        case whatsapp
        case sms
    }

    enum BindingStatus: String, Codable {
        case pending
        case linked
        case disabled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case role
        case permission
        case notificationChannel = "notification_channel"
        case phoneNumber = "phone_number"
        case avatarEmoji = "avatar_emoji"
        case notificationsEnabled = "notifications_enabled"
        case inviteToken = "invite_token"
        case bindingStatus = "binding_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
