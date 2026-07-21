import SwiftUI

enum LedgerCategoryIconPresets {
    /// 30 个常用记账分类图标（emoji）。
    static let all: [String] = [
        "🍔", "🚗", "🛒", "🏃", "✈️",
        "🔧", "🏠", "💊", "🎓", "👶",
        "🎁", "📱", "👕", "🎬", "☕",
        "🍕", "🚌", "⛽", "💡", "🐕",
        "💼", "↩️", "💰", "🏦", "📈",
        "🎮", "📚", "🧾", "🎉", "🏷️"
    ]

    static func resolvedSelection(from current: String) -> String {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return all[29] }
        if all.contains(trimmed) { return trimmed }
        return trimmed
    }

    static func options(including current: String) -> [String] {
        let selected = resolvedSelection(from: current)
        if all.contains(selected) { return all }
        return [selected] + all
    }
}

struct LedgerCategoryIconPicker: View {
    @Binding var selectedIcon: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(LedgerCategoryIconPresets.options(including: selectedIcon), id: \.self) { icon in
                Button {
                    selectedIcon = icon
                } label: {
                    Text(icon)
                        .font(.title2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedIcon == icon ? Color.accentColor.opacity(0.18) : Color(.secondarySystemFill))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    selectedIcon == icon ? Color.accentColor : Color.clear,
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon)
                .accessibilityAddTraits(selectedIcon == icon ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }
}
