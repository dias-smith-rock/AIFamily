import SwiftUI

/// Live Huddle 地图标注：紧凑头像 + 可选朝向（绕头像圆心旋转，电量在下方不遮挡）。
struct LivePeerMapMarker: View {
    let displayName: String
    let batteryLevel: Int
    let isCharging: Bool
    var lastUpdatedAt: Date?
    var headingDegrees: Double?

    private var avatarRadius: CGFloat { UserMapAvatarView.avatarDiameter / 2 }

    /// 画布边长：容纳涟漪放大后仍绕头像圆心。
    static var markerCanvasSide: CGFloat {
        UserMapAvatarView.avatarDiameter * maxRippleScale + 16
    }

    private static let maxRippleScale: CGFloat = 2.15
    private static let innerRippleScale: CGFloat = 1.75
    private static let batteryAreaHeight: CGFloat = 22
    private static let batterySpacing: CGFloat = 5
    private static let rippleDuration: TimeInterval = 1.8
    private static let innerRippleDelay: TimeInterval = 0.85

    /// 地图坐标落在头像圆心（而非整块标注含电量的几何中心）。
    static var mapCoordinateAnchor: UnitPoint {
        let totalHeight = markerCanvasSide + batterySpacing + batteryAreaHeight
        return UnitPoint(x: 0.5, y: (markerCanvasSide / 2) / totalHeight)
    }

    var body: some View {
        VStack(spacing: Self.batterySpacing) {
            ZStack {
                LiveRippleRingsCanvas(
                    avatarDiameter: UserMapAvatarView.avatarDiameter,
                    canvasSide: Self.markerCanvasSide,
                    maxScale: Self.maxRippleScale,
                    innerScale: Self.innerRippleScale,
                    duration: Self.rippleDuration,
                    innerDelay: Self.innerRippleDelay
                )
                .allowsHitTesting(false)

                headingIndicator

                MapAvatarRingView(
                    displayName: displayName,
                    batteryLevel: batteryLevel,
                    isCharging: isCharging
                )
            }
            .frame(width: Self.markerCanvasSide, height: Self.markerCanvasSide)

            MapAvatarInfoBadge(
                batteryLevel: batteryLevel,
                isCharging: isCharging,
                lastUpdatedAt: lastUpdatedAt
            )
        }
    }

    @ViewBuilder
    private var headingIndicator: some View {
        if let headingDegrees {
            ZStack {
                HeadingWedgeShape(
                    innerRadius: avatarRadius,
                    outerRadius: Self.markerCanvasSide / 2 - 4
                )
                .fill(Color.blue.opacity(0.28))

                HeadingWedgeShape(
                    innerRadius: avatarRadius + 2,
                    outerRadius: Self.markerCanvasSide / 2 - 3
                )
                .stroke(Color.blue.opacity(0.55), lineWidth: 1.5)

                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 14, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.blue)
                    .offset(y: -(Self.markerCanvasSide / 2 - 8))
            }
            .frame(width: Self.markerCanvasSide, height: Self.markerCanvasSide)
            .rotationEffect(.degrees(headingDegrees))
            .animation(.linear(duration: 0.12), value: headingDegrees)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Ripple (Canvas，圆心与头像几何中心一致)

private struct LiveRippleRingsCanvas: View {
    let avatarDiameter: CGFloat
    let canvasSide: CGFloat
    let maxScale: CGFloat
    let innerScale: CGFloat
    let duration: TimeInterval
    let innerDelay: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let baseRadius = avatarDiameter / 2
                let elapsed = timeline.date.timeIntervalSinceReferenceDate

                drawRipple(
                    context: &context,
                    center: center,
                    baseRadius: baseRadius,
                    phase: ripplePhase(elapsed: elapsed, delay: 0),
                    maxScale: maxScale,
                    strokeOpacity: 0.5,
                    lineWidth: 2
                )
                drawRipple(
                    context: &context,
                    center: center,
                    baseRadius: baseRadius,
                    phase: ripplePhase(elapsed: elapsed, delay: innerDelay),
                    maxScale: innerScale,
                    strokeOpacity: 0.65,
                    lineWidth: 1.5
                )
            }
        }
        .frame(width: canvasSide, height: canvasSide)
    }

    private func ripplePhase(elapsed: TimeInterval, delay: TimeInterval) -> CGFloat {
        let shifted = elapsed - delay
        guard shifted >= 0 else { return 0 }
        let cycle = shifted.truncatingRemainder(dividingBy: duration)
        return CGFloat(cycle / duration)
    }

    private func drawRipple(
        context: inout GraphicsContext,
        center: CGPoint,
        baseRadius: CGFloat,
        phase: CGFloat,
        maxScale: CGFloat,
        strokeOpacity: Double,
        lineWidth: CGFloat
    ) {
        let scale = 1 + (maxScale - 1) * phase
        let radius = baseRadius * scale
        let opacity = (1 - phase) * strokeOpacity

        var ring = Path()
        ring.addEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))

        context.stroke(
            ring,
            with: .color(Color.green.opacity(opacity)),
            style: StrokeStyle(lineWidth: lineWidth)
        )
    }
}

// MARK: - Avatar ring & battery (shared with UserMapAvatarView)

struct MapAvatarRingView: View {
    let displayName: String
    let batteryLevel: Int
    let isCharging: Bool
    var mapAccentColor: Color?

    private var ringColor: Color {
        if isCharging { return .green }
        if batteryLevel <= 20 { return .red }
        return mapAccentColor ?? .blue
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor, lineWidth: UserMapAvatarView.ringLineWidth)

            Image(systemName: "person.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityLabel(displayName)
        }
        .frame(width: UserMapAvatarView.avatarDiameter, height: UserMapAvatarView.avatarDiameter)
    }
}

struct MapAvatarBatteryBadge: View {
    let batteryLevel: Int
    let isCharging: Bool

    static let badgeHeight: CGFloat = 16

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
        .frame(height: Self.badgeHeight)
    }
}

struct MapAvatarLastUpdatedBadge: View {
    let lastUpdatedAt: Date

    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            Text(LocationRelativeTimeFormatting.mapBadgeText(since: lastUpdatedAt, locale: locale))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
                .frame(height: MapAvatarBatteryBadge.badgeHeight)
        }
    }
}

/// 历史轨迹点：圆点 + 可选电量/时间轮播（锚点在圆心）。
struct MapHistoryTrajectoryMarker: View {
    let dotDiameter: CGFloat
    let dotColor: Color
    let batteryLevel: Int?
    let isCharging: Bool
    let recordedAt: Date?

    private static let badgeSpacing: CGFloat = 4

    private var showsInfoBadge: Bool {
        batteryLevel != nil || recordedAt != nil
    }

    static func mapCoordinateAnchor(dotDiameter: CGFloat, showsInfoBadge: Bool) -> UnitPoint {
        guard showsInfoBadge else { return .center }
        let totalHeight = dotDiameter + badgeSpacing + MapAvatarBatteryBadge.badgeHeight
        return UnitPoint(x: 0.5, y: (dotDiameter / 2) / totalHeight)
    }

    var body: some View {
        VStack(spacing: Self.badgeSpacing) {
            Circle()
                .fill(dotColor)
                .frame(width: dotDiameter, height: dotDiameter)

            infoBadge
        }
    }

    @ViewBuilder
    private var infoBadge: some View {
        if let batteryLevel {
            MapAvatarInfoBadge(
                batteryLevel: min(100, max(0, batteryLevel)),
                isCharging: isCharging,
                lastUpdatedAt: recordedAt
            )
        } else if let recordedAt {
            MapAvatarLastUpdatedBadge(lastUpdatedAt: recordedAt)
        }
    }
}

/// 地图标注底部信息：电量 ↔ 位置更新时间轮播。
struct MapAvatarInfoBadge: View {
    let batteryLevel: Int
    let isCharging: Bool
    let lastUpdatedAt: Date?

    private static let carouselInterval: TimeInterval = 3

    var body: some View {
        Group {
            if let lastUpdatedAt {
                TimelineView(.periodic(from: .now, by: Self.carouselInterval)) { timeline in
                    let showBattery = Int(timeline.date.timeIntervalSinceReferenceDate / Self.carouselInterval) % 2 == 0
                    ZStack {
                        MapAvatarBatteryBadge(
                            batteryLevel: batteryLevel,
                            isCharging: isCharging
                        )
                        .opacity(showBattery ? 1 : 0)

                        MapAvatarLastUpdatedBadge(lastUpdatedAt: lastUpdatedAt)
                            .opacity(showBattery ? 0 : 1)
                    }
                    .animation(.easeInOut(duration: 0.28), value: showBattery)
                }
            } else {
                MapAvatarBatteryBadge(
                    batteryLevel: batteryLevel,
                    isCharging: isCharging
                )
            }
        }
        .frame(height: MapAvatarBatteryBadge.badgeHeight)
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
        Text(L10n.Common.live2.localized)
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
    ZStack {
        Color.black.opacity(0.85)
        LivePeerMapMarker(displayName: "Dad", batteryLevel: 100, isCharging: false, lastUpdatedAt: Date().addingTimeInterval(-8 * 60), headingDegrees: 90)
    }
    .padding(40)
}
