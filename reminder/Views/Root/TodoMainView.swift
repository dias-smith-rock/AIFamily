import SwiftUI

/// 待办 Tab 根入口。
struct TodoMainView: View {
    var body: some View {
        TodoListView()
    }
}

#Preview {
    TodoMainView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
