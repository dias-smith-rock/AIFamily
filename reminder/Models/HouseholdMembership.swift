import Foundation

// MARK: - 2. 家庭成员关系 (HouseholdMembership)
/// `userId` 为空表示影子成员（未注册账号、由管理员代建）。
struct HouseholdMembership: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    var userId: UUID?
    var role: MembershipRole
    var nickname: String
    var avatarUrl: String?
    var contactMethod: ContactMethod
    var phoneNumber: String?
    var email: String?
    var status: MembershipStatus
    var joinedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}
