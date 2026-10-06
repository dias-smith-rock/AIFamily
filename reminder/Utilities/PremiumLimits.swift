import Foundation

/// 免费版 / Pro 版客户端配额（与 VIP 页宣传一致）。
enum PremiumLimits {
    static let freeMaxHouseholds = 1
    /// 免费版每组活跃成员上限（含创建者）；双职工家庭试用需容纳配偶与孩子档案/真人。
    static let freeMaxMembersPerHousehold = 6
    static let freeMaxTaskAttachments = 1
    static let proMaxTaskAttachments = 10
    /// 免费版地图最多展示 3 个历史点；Pro 可选更高档位或不限。
    static let freeMaxMapHistoryDisplayCount = 3

    static func canCreateOrJoinAnotherHousehold(currentCount: Int, hasPremium: Bool) -> Bool {
        hasPremium || currentCount < freeMaxHouseholds
    }

    static func canAddHouseholdMember(currentActiveCount: Int, hasPremium: Bool) -> Bool {
        hasPremium || currentActiveCount < freeMaxMembersPerHousehold
    }

    static func maxTaskAttachments(hasPremium: Bool) -> Int {
        hasPremium ? proMaxTaskAttachments : freeMaxTaskAttachments
    }

    static func canSetMapHistoryDisplayCount(_ count: Int, hasPremium: Bool) -> Bool {
        if LocationMapDisplayPreferences.isUnlimited(count) { return hasPremium }
        return hasPremium || count <= freeMaxMapHistoryDisplayCount
    }

    static func clampedMapHistoryDisplayCount(_ count: Int, hasPremium: Bool) -> Int {
        let normalized = LocationMapDisplayPreferences.normalizedCount(count)
        guard hasPremium else {
            if LocationMapDisplayPreferences.isUnlimited(normalized) {
                return freeMaxMapHistoryDisplayCount
            }
            return min(normalized, freeMaxMapHistoryDisplayCount)
        }
        return normalized
    }

    static func canEnableLocationGhostMode(hasPremium: Bool) -> Bool {
        hasPremium
    }

    static func canUseAIPhotoTaskCreation(hasPremium: Bool) -> Bool {
        hasPremium
    }
}
