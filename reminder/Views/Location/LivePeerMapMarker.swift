import SwiftUI

/// Live Huddle 地图标注：紧凑头像 + 可选朝向（绕头像圆心旋转，电量在下方不遮挡）。
struct LivePeerMapMarker: View {
    let displayName: String
    let batteryLevel: Int
    let isCharging: Bool
    var headingDegrees: Double?

    @State private var rippleOuter = false
    @State private var rippleInner = false

    /// 朝向层边长；头像圆心即该框中心，保证旋转不偏。
    private let headingCanvasSize: CGFloat = 58
    private var avatarRadius: CGFloat { UserMapAvatarView.avatarDiameter / 2 }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                rippleRing(isOuter: true)
                rippleRing(isOuter: false)
                headingIndicator
                MapAvatarRingView(
                    displayName: displayName,
                    batteryLevel: batteryLevel,
                    isCharging: isCharging
                )
            }
            .frame(width: headingCanvasSize, height: headingCanvasSize)

            MapAvatarBatteryBadge(
                batteryLevel: batteryLevel,
                isCharging: isCharging
            )
        }
        .onAppear {
            rippleOuter = true
            rippleInner = true
        }
    }

    @ViewBuilder
    private var headingIndicator: some View {
        if let headingDegrees {
            ZStack {
                HeadingWedgeShape(
                    innerRadius: avatarRadius,
                    outerRadius: headingCanvasSize / 2 - 2
                )
                .fill(Color.blue.opacity(0.28))

                HeadingWedgeShape(
                    innerRadius: avatarRadius + 2,
                    outerRadius: headingCanvasSize / 2 - 1
                )
                .stroke(Color.blue.opacity(0.55), lineWidth: 1.5)

                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 14, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.blue)
                    .offset(y: -(headingCanvasSize / 2 - 6))
            }
            .frame(width: headingCanvasSize, height: headingCanvasSize)
            .rotationEffect(.degrees(headingDegrees))
            .animation(.linear(duration: 0.12), value: headingDegrees)
        }
    }

    private func rippleRing(isOuter: Bool) -> some View {
        let base = UserMapAvatarView.avatarDiameter + 6
        return Circle()
            .stroke(Color.green.opacity(isOuter ? 0.4 : 0.6), lineWidth: isOuter ? 1.5 : 2)
            .frame(width: base, height: base)
            .scaleEffect(isOuter ? (rippleOuter ? 2.2 : 1) : (rippleInner ? 2.2 : 1))
            .opacity(isOuter ? (rippleOuter ? 0 : 0.5) : (rippleInner ? 0 : 0.7))
            .animation(
                .easeOut(duration: 1.8)
                    .repeatForever(autoreverses: false)
                    .delay(isOuter ? 0 : 0.85),
                value: isOuter ? rippleOuter : rippleInner
            )
    }
}

// MARK: - Avatar ring & battery (shared with UserMapAvatarView)

struct MapAvatarRingView: View {
    let displayName: String
    let batteryLevel: Int
    let isCharging: Bool

    private var ringColor: Color {
        if isCharging { return .green }
        if batteryLevel <= 20 { return .red }
        return .blue
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor, lineWidth: UserMapAvatarView.ringLineWidth)
                .frame(
                    width: UserMapAvatarView.avatarDiameter,
                    height: UserMapAvatarView.avatarDiameter
                )

            Image(systemName: "person.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: UserMapAvatarView.personIconSize))
                .foregroundStyle(.secondary)
                .accessibilityLabel(displayName)
        }
    }
}

struct MapAvatarBatteryBadge: View {
    let batteryLevel: Int
    let isCharging: Bool

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

/// 绕圆心向上的扇形环（顶点在圆心，开口朝 -Y），与头像描边外缘对齐。
private struct HeadingWedgeShape: Shape {
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var spreadDegrees: CGFloat = 38

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let half = Angle(degrees: Double(spreadDegrees) / 2)
        let up = Angle(degrees: -90)

        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: up - half,
            endAngle: up + half,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: up + half,
            endAngle: up - half,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

struct LiveTrackingBadge: View {
    @State private var glow = false

    var body: some View {
        Text("LIVE")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(Color.green)
                    .shadow(color: Color.green.opacity(glow ? 0.85 : 0.25), radius: glow ? 8 : 2)
            }
            .scaleEffect(glow ? 1.04 : 0.96)
            .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: glow)
            .onAppear { glow = true }
    }
}

#Preview {
    VStack(spacing: 32) {
        LivePeerMapMarker(displayName: "李雨桐", batteryLevel: 72, isCharging: false, headingDegrees: 45)
        LivePeerMapMarker(displayName: "王晓明", batteryLevel: 88, isCharging: true, headingDegrees: 0)
        LiveTrackingBadge()
    }
    .padding()
}
