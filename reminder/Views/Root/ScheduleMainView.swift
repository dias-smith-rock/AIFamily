import SwiftUI

/// 日程 Tab 根入口。
struct ScheduleMainView: View {
    var body: some View {
        TaskListView()
    }
}

#Preview {
    ScheduleMainView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
