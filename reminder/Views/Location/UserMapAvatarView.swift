import SwiftUI

/// 地图成员标注头像（普通 / Live 模式统一紧凑尺寸）。
struct UserMapAvatarView: View {
    static let avatarDiameter: CGFloat = 30
    static let personIconSize: CGFloat = 24
    static let ringLineWidth: CGFloat = 2

    let displayName: String
    let batteryLevel: Int
    let isCharging: Bool

    private var ringColor: Color {
        if isCharging {
            return .green
        }
        if batteryLevel <= 20 {
            return .red
        }
        return .blue
    }

    private var batterySymbol: String {
        switch batteryLevel {
        case 0 ... 10: "battery.0percent"
        case 11 ... 35: "battery.25percent"
        case 36 ... 60: "battery.50percent"
        case 61 ... 85: "battery.75percent"
        default: "battery.100percent"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(ringColor, lineWidth: Self.ringLineWidth)
                    .frame(width: Self.avatarDiameter, height: Self.avatarDiameter)

                Image(systemName: "person.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: Self.personIconSize))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(displayName)
            }

            HStack(spacing: 2) {
                Image(systemName: isCharging ? "bolt.fill" : batterySymbol)
                    .font(.system(size: 8, weight: .semibold))
                Text("\(batteryLevel)%")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

#Preview {
    UserMapAvatarView(displayName: "王晓明", batteryLevel: 45, isCharging: false)
        .padding()
}
