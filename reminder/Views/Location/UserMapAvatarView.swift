import SwiftUI

struct UserMapAvatarView: View {
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
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(ringColor, lineWidth: 3)
                    .frame(width: 48, height: 48)

                Image(systemName: "person.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(displayName)
            }

            HStack(spacing: 3) {
                Image(systemName: isCharging ? "bolt.fill" : batterySymbol)
                    .font(.caption2.weight(.semibold))
                Text("\(batteryLevel)%")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

#Preview {
    UserMapAvatarView(displayName: "王晓明", batteryLevel: 45, isCharging: false)
        .padding()
}
