import SwiftUI

/// 地图成员标注头像（普通 / Live 模式统一紧凑尺寸）。
struct UserMapAvatarView: View {
    static let avatarDiameter: CGFloat = 34
    static let personIconSize: CGFloat = 26
    static let ringLineWidth: CGFloat = 2.5

    let displayName: String
    let batteryLevel: Int
    let isCharging: Bool
    var lastUpdatedAt: Date?
    var mapAccentColor: Color?
    var avatarURL: URL?

    var body: some View {
        VStack(spacing: 2) {
            MapAvatarRingView(
                displayName: displayName,
                batteryLevel: batteryLevel,
                isCharging: isCharging,
                mapAccentColor: mapAccentColor,
                avatarURL: avatarURL
            )
            MapAvatarInfoBadge(
                batteryLevel: batteryLevel,
                isCharging: isCharging,
                lastUpdatedAt: lastUpdatedAt
            )
            MapAvatarNameCaption(displayName: displayName)
        }
    }

    /// 含白色描边光晕后的头像占位高度。
    static var avatarPlateDiameter: CGFloat { avatarDiameter + 4 }

    /// 地图坐标落在头像圆心（名称与电量在下方）。
    static var mapCoordinateAnchor: UnitPoint {
        let spacing: CGFloat = 2
        let totalHeight = avatarPlateDiameter
            + spacing
            + MapAvatarBatteryBadge.badgeHeight
            + spacing
            + MapAvatarNameCaption.height
        return UnitPoint(x: 0.5, y: (avatarPlateDiameter / 2) / totalHeight)
    }
}

#Preview {
    UserMapAvatarView(displayName: "王晓明", batteryLevel: 45, isCharging: false)
        .padding()
}
