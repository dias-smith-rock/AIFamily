import SwiftUI

struct LivePeerMapMarker: View {
    let displayName: String
    let batteryLevel: Int
    let isCharging: Bool

    @State private var rippleOuter = false
    @State private var rippleInner = false

    var body: some View {
        ZStack {
            rippleRing(isOuter: true)
            rippleRing(isOuter: false)

            UserMapAvatarView(
                displayName: displayName,
                batteryLevel: batteryLevel,
                isCharging: isCharging
            )
        }
        .onAppear {
            rippleOuter = true
            rippleInner = true
        }
    }

    private func rippleRing(isOuter: Bool) -> some View {
        Circle()
            .stroke(Color.green.opacity(isOuter ? 0.45 : 0.65), lineWidth: isOuter ? 2 : 2.5)
            .frame(width: 56, height: 56)
            .scaleEffect(isOuter ? (rippleOuter ? 2.5 : 1) : (rippleInner ? 2.5 : 1))
            .opacity(isOuter ? (rippleOuter ? 0 : 0.55) : (rippleInner ? 0 : 0.75))
            .animation(
                .easeOut(duration: 1.8)
                    .repeatForever(autoreverses: false)
                    .delay(isOuter ? 0 : 0.85),
                value: isOuter ? rippleOuter : rippleInner
            )
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
        LivePeerMapMarker(displayName: "李雨桐", batteryLevel: 72, isCharging: false)
        LiveTrackingBadge()
    }
    .padding()
}
