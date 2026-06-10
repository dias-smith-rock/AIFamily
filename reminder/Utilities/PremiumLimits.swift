import Foundation

/// 免费版 / Pro 版客户端配额（与 VIP 页宣传一致）。
enum PremiumLimits {
    static let freeMaxHouseholds = 1
    static let freeMaxMembersPerHousehold = 2
    static let freeMaxTaskAttachments = 1
    static let proMaxTaskAttachments = 10

    static func canCreateOrJoinAnotherHousehold(currentCount: Int, hasPremium: Bool) -> Bool {
        hasPremium || currentCount < freeMaxHouseholds
    }

    static func canAddHouseholdMember(currentActiveCount: Int, hasPremium: Bool) -> Bool {
        hasPremium || currentActiveCount < freeMaxMembersPerHousehold
    }

    static func maxTaskAttachments(hasPremium: Bool) -> Int {
        hasPremium ? proMaxTaskAttachments : freeMaxTaskAttachments
    }
}
