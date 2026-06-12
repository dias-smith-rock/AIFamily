import SwiftUI

/// 提醒偏移（分钟）→ String Catalog 键（与 `CreateTaskView` / 详情页共用）。
enum TaskReminderLabel {
    static func titleKey(forMinutes minutes: Int) -> LocalizedStringKey {
        switch minutes {
        case 0: L10n.Common.onTime.localized
        case 5: L10n.Common.n5MinutesBefore.localized
        case 10: L10n.Common.n10MinutesBefore.localized
        case 15: L10n.Common.n15MinutesBefore.localized
        case 30: L10n.Common.n30MinutesBefore.localized
        case 60: L10n.Common.n1HourBefore.localized
        default: L10n.Common.lldMinutesBefore.localized
        }
    }

    @ViewBuilder
    static func valueView(offsets: [Int]?) -> some View {
        if let offsets, offsets.isEmpty == false {
            let sorted = offsets.sorted()
            HStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { index, minutes in
                    if index > 0 {
                        Text(verbatim: ", ")
                    }
                    switch minutes {
                    case 0, 5, 10, 15, 30, 60:
                        Text(titleKey(forMinutes: minutes))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    default:
                        CustomReminderOffsetText(minutes: minutes)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: true, vertical: false)
        } else {
            Text(L10n.Common.none.localized)
        }
    }
}

private struct CustomReminderOffsetText: View {
    @Environment(\.locale) private var locale
    let minutes: Int

    var body: some View {
        Text(
            verbatim: String(
                format: AppLocalized.string(L10n.Common.lldMinutesBefore, locale: locale),
                locale: locale,
                minutes
            )
        )
    }
}
