import SwiftUI

/// 提醒偏移（分钟）→ String Catalog 键（与 `CreateTaskView` / 详情页共用）。
enum TaskReminderLabel {
    static func titleKey(forMinutes minutes: Int) -> LocalizedStringKey {
        switch minutes {
        case 0: "On time"
        case 5: "5 minutes before"
        case 10: "10 minutes before"
        case 15: "15 minutes before"
        case 30: "30 minutes before"
        case 60: "1 hour before"
        default: "%lld minutes before"
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
                    default:
                        Text("\(minutes) minutes before")
                    }
                }
            }
        } else {
            Text("None")
        }
    }
}
