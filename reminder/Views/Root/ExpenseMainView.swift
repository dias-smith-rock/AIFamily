import SwiftUI

/// 账本 Tab 占位页（后续接入独立 Expenses 模块）。
struct ExpenseMainView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.white.opacity(0.88))
                    .symbolRenderingMode(.hierarchical)

                Text(L10n.Common.comingSoon.localized)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

#Preview {
    ExpenseMainView()
}
