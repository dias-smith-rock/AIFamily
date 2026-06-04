import SwiftUI

/// 地图成员标注头像（普通 / Live 模式统一紧凑尺寸）。
struct UserMapAvatarView: View {
    static let avatarDiameter: CGFloat = 30
    static let personIconSize: CGFloat = 24
    static let ringLineWidth: CGFloat = 2

    let displayName: String
    let batteryLevel: Int
    let isCharging: Bool
    var mapAccentColor: Color?

    var body: some View {
        VStack(spacing: 2) {
            MapAvatarRingView(
                displayName: displayName,
                batteryLevel: batteryLevel,
                isCharging: isCharging,
                mapAccentColor: mapAccentColor
            )
            MapAvatarBatteryBadge(
                batteryLevel: batteryLevel,
                isCharging: isCharging
            )
        }
    }
}

#Preview {
    UserMapAvatarView(displayName: "王晓明", batteryLevel: 45, isCharging: false)
        .padding()
}
