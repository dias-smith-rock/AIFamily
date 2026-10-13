import Foundation

/// MapKit Directions 贴路限制（服务端只存稀疏锚点，贴路在客户端完成）。
enum LocationRoadSnapPreferences {
    /// 单次 rebuild 每成员最多贴路的轨迹段数（按 endedAt 新→旧）。
    static let maxSegmentsPerMemberFree = 6
    static let maxSegmentsPerMemberPremium = 8

    /// 同时进行 Directions 计算的上限。次数不封顶，只限制并发，避免 MapKit 直接拒绝。
    static let maxConcurrentDirections = 2

    static func maxSegmentsPerMember(hasPremium: Bool) -> Int {
        if VIPFeatureGate.isEnabled == false || hasPremium {
            return maxSegmentsPerMemberPremium
        }
        return maxSegmentsPerMemberFree
    }
}
