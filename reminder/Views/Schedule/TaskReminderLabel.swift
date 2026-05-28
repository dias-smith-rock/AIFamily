import SwiftUI

/// 提醒偏移（分钟）→ String Catalog 键（与 `CreateTaskView` / 详情页共用）。
enum TaskReminderLabel {
    static func titleKey(forMinutes minutes: Int) -> LocalizedStringKey {
        switch minutes {
        case 0: "准时"
        case 5: "提前5分钟"
        case 10: "提前10分钟"
        case 15: "提前15分钟"
        case 30: "提前30分钟"
        case 60: "提前1小时"
        default: "提前%lld分钟"
        }
    }

    @ViewBuilder
    static func valueView(offsets: [Int]?) -> some View {
        if let offsets, offsets.isEmpty == false {
            let sorted = offsets.sorted()
            HStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { index, minutes in
                    if index > 0 {
                        Text(", ")
                    }
                    switch minutes {
                    case 0, 5, 10, 15, 30, 60:
                        Text(titleKey(forMinutes: minutes))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    default:
                        Text("提前\(minutes)分钟")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: true, vertical: false)
        } else {
            Text("无")
        }
    }
}
