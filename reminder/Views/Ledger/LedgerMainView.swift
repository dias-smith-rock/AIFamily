import SwiftUI

struct LedgerMainView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @StateObject private var viewModel = AppViewModels.makeLedgerViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if canAccessFamilyExpense {
                    FamilyExpenseDashboardView(
                        viewModel: viewModel,
                        allowsExpenseManagement: true
                    )
                } else if canRecordIncome {
                    FamilyExpenseDashboardView(
                        viewModel: viewModel,
                        allowsExpenseManagement: false
                    )
                } else {
                    ContentUnavailableView {
                        Label(
                            L10n.Ledger.memberExpenseUnavailable.localized,
                            systemImage: "lock.fill"
                        )
                    } description: {
                        Text(L10n.Ledger.memberExpenseUnavailableMessage.localized)
                    }
                }
            }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    GroupSwitcherToolbarButton()
                }
            }
            .task(id: ledgerLoadTrigger) {
                viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
                guard appRouter.hasCompletedAuthBootstrap else { return }
                await viewModel.loadRoster()
                if canAccessWalletData {
                    // 分类为空时强制重拉，避免错误缓存
                    let forceReload = viewModel.categories.isEmpty
                    await viewModel.loadLedgerData(force: forceReload)
                }
                await ExchangeRateStore.shared.ensureRatesFresh()
            }
            .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
                viewModel.setHouseholdContext(newValue)
                Task {
                    guard appRouter.hasCompletedAuthBootstrap else { return }
                    await viewModel.loadRoster()
                    if canAccessWalletData {
                        await viewModel.loadLedgerData(force: true)
                    }
                }
            }
            .onChange(of: appRouter.selectedMembershipId) { _, _ in
                Task {
                    await viewModel.loadRoster()
                    if canAccessWalletData {
                        await viewModel.loadLedgerData(force: true)
                    }
                }
            }
        }
        .appLocaleEnvironment(using: appSettings)
    }

    private var ledgerLoadTrigger: String {
        [
            appRouter.selectedHouseholdId?.uuidString ?? "none",
            appRouter.selectedMembershipId?.uuidString ?? "none",
            appSettings.selectedLanguage.id,
            appSettings.ledgerDisplayCurrency
        ].joined(separator: "|")
    }

    private var canAccessFamilyExpense: Bool {
        LedgerAccessControl.canAccessFamilyExpense(role: resolvedMembershipRole)
    }

    private var canRecordIncome: Bool {
        LedgerAccessControl.canRecordIncome(role: resolvedMembershipRole)
    }

    private var canAccessWalletData: Bool {
        canAccessFamilyExpense || canRecordIncome
    }

    private var resolvedMembershipRole: MembershipRole {
        guard let membershipId = appRouter.selectedMembershipId,
              let membership = viewModel.householdMembers.first(where: { $0.id == membershipId }),
              let role = membership.parsedRole else {
            // Before roster loads, try not to flash expense UI for members:
            // default deny until we know role (safer for privacy).
            if viewModel.householdMembers.isEmpty, appRouter.selectedMembershipId != nil {
                return .member
            }
            return .member
        }
        return role
    }
}

#Preview("Creator") {
    LedgerMainView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
