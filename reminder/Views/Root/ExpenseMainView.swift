import SwiftUI

/// 账盘 Tab 入口（Wallet / Ledger）。
struct ExpenseMainView: View {
    var body: some View {
        LedgerMainView()
    }
}

#Preview {
    ExpenseMainView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
