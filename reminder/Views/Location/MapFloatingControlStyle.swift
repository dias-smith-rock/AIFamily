import SwiftUI

/// 地图上浮层圆形按钮底板：提高在浅色/绿色地图上的识别度。
enum MapFloatingControlStyle {
    static let defaultDiameter: CGFloat = 44
    static let largeDiameter: CGFloat = 48
}

private struct MapFloatingControlPlate: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(Color(.systemBackground).opacity(0.96))
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
            .overlay {
                Circle()
                    .strokeBorder(Color(.separator).opacity(0.85), lineWidth: 1)
            }
    }
}

extension View {
    func mapFloatingControlPlate(diameter: CGFloat = MapFloatingControlStyle.defaultDiameter) -> some View {
        frame(width: diameter, height: diameter)
            .background {
                MapFloatingControlPlate(diameter: diameter)
            }
    }
}
