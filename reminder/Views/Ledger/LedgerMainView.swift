import SwiftUI

struct LedgerMainView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @StateObject private var viewModel = AppViewModels.makeLedgerViewModel()
    @State private var currentSegment: FamilyLedgerViewModel.Segment = .expense

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if canAccessFamilyExpense {
                    Picker("", selection: $currentSegment) {
                        Text(L10n.Ledger.familyExpense.localized).tag(FamilyLedgerViewModel.Segment.expense)
                        Text(L10n.Ledger.behaviorPoints.localized).tag(FamilyLedgerViewModel.Segment.points)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }

                Group {
                    switch effectiveSegment {
                    case .expense:
                        FamilyExpenseDashboardView(viewModel: viewModel)
                    case .points:
                        KidsPointsDashboardView(
                            viewModel: viewModel,
                            canManageHousehold: canAccessFamilyExpense
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle(L10n.Ledger.wallet.localized)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    GroupSwitcherToolbarButton()
                }
            }
            .task(id: ledgerLoadTrigger) {
                bindHouseholdContext()
                guard appRouter.hasCompletedAuthBootstrap else { return }
                await viewModel.loadInitialDataIfNeeded()
                applySegmentSandbox()
                viewModel.configurePointsContext(
                    membershipId: appRouter.selectedMembershipId,
                    canManageHousehold: canAccessFamilyExpense
                )
            }
            .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
                viewModel.setHouseholdContext(newValue)
                Task {
                    guard appRouter.hasCompletedAuthBootstrap else { return }
                    await viewModel.loadInitialData(force: true)
                    applySegmentSandbox()
                    viewModel.configurePointsContext(
                        membershipId: appRouter.selectedMembershipId,
                        canManageHousehold: canAccessFamilyExpense
                    )
                }
            }
            .onChange(of: appRouter.selectedMembershipId) { _, _ in
                applySegmentSandbox()
                viewModel.configurePointsContext(
                    membershipId: appRouter.selectedMembershipId,
                    canManageHousehold: canAccessFamilyExpense
                )
            }
            .onChange(of: canAccessFamilyExpense) { _, _ in
                applySegmentSandbox()
            }
        }
        .appLocaleEnvironment(using: appSettings)
    }

    private var ledgerLoadTrigger: String {
        [
            appRouter.selectedHouseholdId?.uuidString ?? "none",
            appRouter.selectedMembershipId?.uuidString ?? "none",
            appSettings.selectedLanguage.id
        ].joined(separator: "|")
    }

    private var canAccessFamilyExpense: Bool {
        LedgerAccessControl.canAccessFamilyExpense(role: resolvedMembershipRole)
    }

    private var effectiveSegment: FamilyLedgerViewModel.Segment {
        canAccessFamilyExpense ? currentSegment : .points
    }

    private var resolvedMembershipRole: MembershipRole {
        guard let membershipId = appRouter.selectedMembershipId,
              let membership = viewModel.householdMembers.first(where: { $0.id == membershipId }),
              let role = membership.parsedRole else {
            return .member
        }
        return role
    }

    private func bindHouseholdContext() {
        viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
    }

    private func applySegmentSandbox() {
        if canAccessFamilyExpense == false {
            currentSegment = .points
        }
    }
}

#Preview("Creator") {
    LedgerMainView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(GroupSwitcherCoordinator())
}
