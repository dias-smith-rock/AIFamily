import SwiftUI

struct PendingView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @State private var breathing = false
    @State private var showToast = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 130, height: 130)
                .overlay {
                    Image(systemName: "person.badge.clock")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .scaleEffect(breathing ? 1.06 : 0.94)
                .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: breathing)

            Text(AppLocalized.string("已敲门，等待管理员批准...", locale: locale))
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)

            Text(AppLocalized.string("批准后你会自动进入群组主界面。", locale: locale))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Button {
                showToast = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    showToast = false
                }
            } label: {
                Text(AppLocalized.string("提醒他快一点", locale: locale))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()

            Button {
                appRouter.goToOrgRouting()
            } label: {
                Text(AppLocalized.string("这不是我家？重新输入", locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            if showToast {
                Text(AppLocalized.string("已催办，管理员会收到提醒", locale: locale))
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            breathing = true
        }
    }
}

#Preview {
    PendingView()
        .environmentObject(AppRouter())
}
