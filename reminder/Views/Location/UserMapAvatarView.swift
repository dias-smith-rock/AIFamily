import SwiftUI

/// 地图成员标注头像（普通 / Live 模式统一紧凑尺寸）。
struct UserMapAvatarView: View {
    static let avatarDiameter: CGFloat = 30
    static let personIconSize: CGFloat = 24
    static let ringLineWidth: CGFloat = 2

    let displayName: String
    let batteryLevel: Int
    let isCharging: Bool
    var lastUpdatedAt: Date?
    var mapAccentColor: Color?
    var avatarURL: URL?
    /// 非 Live：最后上报过久时降饱和，提示「可能离线」。
    var isStale: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            MapAvatarRingView(
                displayName: displayName,
                batteryLevel: batteryLevel,
                isCharging: isCharging,
                mapAccentColor: isStale ? .secondary : mapAccentColor,
                avatarURL: avatarURL
            )
            MapAvatarInfoBadge(
                batteryLevel: batteryLevel,
                isCharging: isCharging,
                lastUpdatedAt: lastUpdatedAt
            )
        }
        .saturation(isStale ? 0.15 : 1)
        .opacity(isStale ? 0.75 : 1)
    }
}

#Preview {
    UserMapAvatarView(displayName: "王晓明", batteryLevel: 45, isCharging: false)
        .padding()
}
