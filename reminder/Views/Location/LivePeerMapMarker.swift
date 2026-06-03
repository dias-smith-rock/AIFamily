import SwiftUI

/// Live Huddle 地图标注：紧凑头像 + 可选朝向扇形（随 `headingDegrees` 旋转）。
struct LivePeerMapMarker: View {
    let displayName: String
    let batteryLevel: Int
    let isCharging: Bool
    var headingDegrees: Double?

    @State private var rippleOuter = false
    @State private var rippleInner = false

    private let rippleDiameter: CGFloat = 36

    var body: some View {
        ZStack {
            rippleRing(isOuter: true)
            rippleRing(isOuter: false)
            headingIndicator
            compactAvatar
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
                HeadingConeShape()
                    .fill(Color.blue.opacity(0.22))
                    .frame(width: 44, height: 52)

                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.blue)
                    .offset(y: -18)
            }
            .rotationEffect(.degrees(headingDegrees))
            .animation(.linear(duration: 0.12), value: headingDegrees)
        }
    }

    private var compactAvatar: some View {
        UserMapAvatarView(
            displayName: displayName,
            batteryLevel: batteryLevel,
            isCharging: isCharging
        )
    }

    private func rippleRing(isOuter: Bool) -> some View {
        Circle()
            .stroke(Color.green.opacity(isOuter ? 0.4 : 0.6), lineWidth: isOuter ? 1.5 : 2)
            .frame(width: rippleDiameter, height: rippleDiameter)
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

/// 指向前方的扇形，默认顶点朝下（与头像中心对齐），由外层 `rotationEffect` 对齐真北。
private struct HeadingConeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let apex = CGPoint(x: rect.midX, y: rect.maxY)
        let spread: CGFloat = 0.42
        path.move(to: apex)
        path.addLine(to: CGPoint(x: rect.minX + rect.width * spread, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * spread, y: rect.minY))
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
    VStack(spacing: 24) {
        LivePeerMapMarker(displayName: "李雨桐", batteryLevel: 72, isCharging: false, headingDegrees: 45)
        LivePeerMapMarker(displayName: "王晓明", batteryLevel: 88, isCharging: true, headingDegrees: nil)
        LiveTrackingBadge()
    }
    .padding()
}
