import SwiftUI

struct LedgerCategoryCard: View {
    let name: String
    let icon: String
    let amountText: String
    let colorHex: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(icon)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(iconTint.opacity(0.22)))

                Text(amountText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var iconTint: Color {
        Color.taskCardLeadingAccent(fromHex: colorHex)
    }

    private var cardBackground: Color {
        guard let colorHex, colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return Color(.secondarySystemBackground)
        }
        return iconTint.opacity(0.14)
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
        LedgerCategoryCard(name: "Transport", icon: "🚌", amountText: "128.50", colorHex: "#007AFF") {}
        LedgerCategoryCard(name: "Food", icon: "🍜", amountText: "0", colorHex: "#FF9500") {}
        LedgerCategoryCard(name: "Home", icon: "🏠", amountText: "2,400", colorHex: "#34C759") {}
    }
    .padding()
}
