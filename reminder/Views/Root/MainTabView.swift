import SwiftUI

struct MainTabView: View {
    @State private var showInviteSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("MainTab L1 占位")
                    .font(.system(size: 28, weight: .bold))
                Text("后续可替换为完整 Tab 架构")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Button {
                    showInviteSheet = true
                } label: {
                    Text("弹出邀请面板")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("家庭主页")
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    MainTabView()
}
