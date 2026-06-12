import SwiftUI

/// 成员详情键值行：标签与占位符使用 `LocalizedStringKey`，由根节点 `\.locale` 驱动翻译。
struct ProfileDetailRowView: View {
    let title: LocalizedStringKey
    let value: String?

    init(title: LocalizedStringKey, value: String?) {
        self.title = title
        self.value = value
    }

    init(title: L10n.Entry, value: String?) {
        self.title = title.localized
        self.value = value
    }

    var body: some View {
        LabeledContent {
            if let display = trimmedValue {
                Text(display)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.Common.notProvided.localized)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
        }
    }

    private var trimmedValue: String? {
        let stable = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stable.isEmpty ? nil : stable
    }
}

/// 成员详情敏感字段行（证件号等）：支持显示/掩码切换。
struct ProfileDetailSensitiveRowView: View {
    let title: LocalizedStringKey
    let value: String?
    @Binding var reveals: Bool

    init(title: LocalizedStringKey, value: String?, reveals: Binding<Bool>) {
        self.title = title
        self.value = value
        self._reveals = reveals
    }

    init(title: L10n.Entry, value: String?, reveals: Binding<Bool>) {
        self.title = title.localized
        self.value = value
        self._reveals = reveals
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let raw = trimmedValue {
                Text(reveals ? raw : maskSensitive(raw))
                    .foregroundStyle(.secondary)
                Button {
                    reveals.toggle()
                } label: {
                    Image(systemName: reveals ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text(L10n.Common.notProvided.localized)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trimmedValue: String? {
        let stable = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stable.isEmpty ? nil : stable
    }

    private func maskSensitive(_ source: String) -> String {
        guard source.count > 8 else { return String(repeating: "*", count: source.count) }
        let prefix = source.prefix(3)
        let suffix = source.suffix(4)
        let stars = String(repeating: "*", count: max(0, source.count - 7))
        return "\(prefix)\(stars)\(suffix)"
    }
}
