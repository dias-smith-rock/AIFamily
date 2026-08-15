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

            Text(AppLocalized.string(L10n.Common.knockedOnTheDoorWaitingForAdministratorAp, locale: locale))
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)

            Text(AppLocalized.string(L10n.Family.afterApprovalYouWillAutomaticallyEnterThe, locale: locale))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Button {
                showToast = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    showToast = false
                }
            } label: {
                Text(AppLocalized.string(L10n.Schedule.remindHimToHurryUp, locale: locale))
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
                Text(AppLocalized.string(L10n.Common.thisIsNotMyHomeReEnter, locale: locale))
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
                Text(AppLocalized.string(L10n.Schedule.itHasBeenUrgedAndTheAdministratorWillRec, locale: locale))
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
            AnalyticsManager.logOnboardingStep(AnalyticsManager.OnboardingStep.pending)
        }
    }
}

#Preview {
    PendingView()
        .environmentObject(AppRouter())
}
