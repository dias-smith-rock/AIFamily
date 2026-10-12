import Foundation

/// MapKit Directions 贴路配额（服务端只存稀疏锚点，贴路在客户端完成）。
enum LocationRoadSnapPreferences {
    /// 单次 rebuild 每成员最多贴路的轨迹段数（按 endedAt 新→旧）。
    static let maxSegmentsPerMemberFree = 6
    static let maxSegmentsPerMemberPremium = 8

    /// 单次 rebuild 最多发起的 Directions 请求次数（相邻锚点对各算一次）。
    static let maxDirectionsRequestsPerRebuild = 40

    /// 同时进行 Directions 计算的上限。
    static let maxConcurrentDirections = 2

    static func maxSegmentsPerMember(hasPremium: Bool) -> Int {
        hasPremium ? maxSegmentsPerMemberPremium : maxSegmentsPerMemberFree
    }
}
