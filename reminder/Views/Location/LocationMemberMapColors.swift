import SwiftUI

/// 位置 Tab 地图：按成员 `id` 稳定分配区分色（轨迹、历史点、头像环）。
enum LocationMemberMapColors {
    private static let palette: [Color] = [
        .blue,
        .orange,
        .purple,
        .teal,
        .pink,
        .indigo,
        .mint,
        .cyan
    ]

    static func accent(for memberId: UUID) -> Color {
        palette[stableIndex(for: memberId) % palette.count]
    }

    /// 轨迹线段颜色：同用户同色，越靠近当前位置越深。
    static func trajectorySegment(
        for memberId: UUID,
        segmentIndex: Int,
        totalSegments: Int
    ) -> Color {
        let base = accent(for: memberId)
        let progress = totalSegments > 0
            ? Double(segmentIndex + 1) / Double(totalSegments)
            : 1
        return base.opacity(0.32 + (0.68 * progress))
    }

    /// 历史点：`rank` 0 = 最旧，递增到最新历史点。
    static func historyDot(for memberId: UUID, rank: Int, totalHistoryCount: Int = 2) -> Color {
        let progress: Double
        if totalHistoryCount > 1 {
            progress = Double(rank) / Double(totalHistoryCount - 1)
        } else {
            progress = 1
        }
        let opacity = 0.38 + (0.37 * progress)
        return accent(for: memberId).opacity(opacity)
    }

    private static func stableIndex(for memberId: UUID) -> Int {
        let bytes = memberId.uuid
        var hash = UInt32(bytes.0)
        hash = hash &* 31 &+ UInt32(bytes.1)
        hash = hash &* 31 &+ UInt32(bytes.2)
        hash = hash &* 31 &+ UInt32(bytes.3)
        hash = hash &* 31 &+ UInt32(bytes.4)
        hash = hash &* 31 &+ UInt32(bytes.5)
        hash = hash &* 31 &+ UInt32(bytes.6)
        hash = hash &* 31 &+ UInt32(bytes.7)
        return Int(hash % UInt32(palette.count))
    }
}
