import SwiftUI

/// VIP 订阅详情占位页；后续接入 StoreKit / 订阅流程时在此扩展。
struct VIPSubscriptionView: View {
    var body: some View {
        ContentUnavailableView {
            Label("升级 VIP", systemImage: "crown.fill")
                .foregroundStyle(.orange)
        } description: {
            Text("VIP 权益即将开放。")
        }
        .navigationTitle("升级 VIP")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        VIPSubscriptionView()
    }
}
