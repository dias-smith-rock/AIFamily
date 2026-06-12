import SwiftUI

/// 任务详情键值行：标签使用 `LocalizedStringKey`，由根节点 `\.locale` 驱动翻译。
struct TaskDetailRowView<Value: View>: View {
    let systemImage: String
    let label: LocalizedStringKey
    var valueIsPlaceholder: Bool = false
    var valueAccent: Bool = false
    @ViewBuilder let value: () -> Value

    init(systemImage: String, label: LocalizedStringKey, valueIsPlaceholder: Bool = false, valueAccent: Bool = false, @ViewBuilder value: @escaping () -> Value) {
        self.systemImage = systemImage
        self.label = label
        self.valueIsPlaceholder = valueIsPlaceholder
        self.valueAccent = valueAccent
        self.value = value
    }

    init(systemImage: String, label: L10n.Entry, valueIsPlaceholder: Bool = false, valueAccent: Bool = false, @ViewBuilder value: @escaping () -> Value) {
        self.init(systemImage: systemImage, label: label.localized, valueIsPlaceholder: valueIsPlaceholder, valueAccent: valueAccent, value: value)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .center)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            value()
                .font(.body.weight(.medium))
                .foregroundStyle(valueForeground)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var valueForeground: Color {
        if valueIsPlaceholder {
            return Color.secondary.opacity(0.75)
        }
        if valueAccent {
            return Color.accentColor
        }
        return Color.primary
    }
}
