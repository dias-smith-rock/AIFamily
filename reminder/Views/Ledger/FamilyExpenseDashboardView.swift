import SwiftUI

struct FamilyExpenseDashboardView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appSettings: AppSettingsManager
    @ObservedObject var viewModel: FamilyLedgerViewModel
    @ObservedObject private var exchangeRates = ExchangeRateStore.shared

    /// `false`：普通成员仅进账（收入网格），不展示支出/报表/分类管理。
    var allowsExpenseManagement: Bool = true

    @State private var expenseExpanded = true
    @State private var incomeExpanded = true
    @State private var entryPrefill: ManualEntryPrefill?
    @State private var isShowingCategoryManager = false
    @State private var manageCategoriesInitialType: LedgerEntryType = .expense
    @State private var isShowingReports = false
    @State private var categoryPendingEdit: ExpenseCategory?
    @State private var categoryPendingDelete: ExpenseCategory?
    @State private var isConfirmingCategoryDelete = false
    @State private var deleteBlockedMessage: String?

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                periodChrome

                if let errorMessage = viewModel.errorMessage, errorMessage.isEmpty == false {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    if allowsExpenseManagement {
                        categorySection(
                            title: L10n.Ledger.expense.localized,
                            total: viewModel.expenseTotalInPeriod,
                            type: .expense,
                            isExpanded: $expenseExpanded
                        )
                    }
                    categorySection(
                        title: L10n.Ledger.income.localized,
                        total: viewModel.incomeTotalInPeriod,
                        type: .income,
                        isExpanded: $incomeExpanded
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 88)
        }
        .refreshable {
            LedgerWalletLoadLogger.step(
                .reloadTapped,
                source: "pull_to_refresh",
                householdId: viewModel.currentHouseholdIdValue
            )
            await viewModel.loadInitialData(force: true, source: "pull_to_refresh")
            await exchangeRates.ensureRatesFresh()
        }
        .task {
            await exchangeRates.ensureRatesFresh()
        }
        .overlay(alignment: .bottomTrailing) {
            logEntryFAB
        }
        .toolbar {
            if allowsExpenseManagement {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingReports = true
                    } label: {
                        Image(systemName: "dollarsign.circle")
                    }
                    .accessibilityLabel(L10n.Ledger.reports.localized)
                }
            }
        }
        .sheet(item: $entryPrefill) { prefill in
            ManualExpenseEntrySheet(
                viewModel: viewModel,
                prefillType: prefill.type,
                prefillCategoryId: prefill.categoryId,
                locksToIncome: allowsExpenseManagement == false
            )
        }
        .sheet(isPresented: $isShowingCategoryManager) {
            ManageCategoriesSheet(
                viewModel: viewModel,
                initialType: manageCategoriesInitialType
            )
        }
        .sheet(isPresented: $isShowingReports) {
            LedgerReportsView(viewModel: viewModel)
        }
        .sheet(item: $categoryPendingEdit) { category in
            EditCategorySheet(viewModel: viewModel, category: category)
        }
        .alert(
            L10n.Ledger.deleteCategory.localized,
            isPresented: $isConfirmingCategoryDelete
        ) {
            Button(L10n.Ledger.deleteCategory, role: .destructive) {
                // 必须先拷贝：alert 关闭时不要依赖仍存活的 pending 状态时序
                guard let category = categoryPendingDelete else {
                    LedgerCategoryDeleteLogger.step(
                        .failed,
                        categoryId: nil,
                        detail: "confirm_action_missing_pending_category source=dashboard"
                    )
                    return
                }
                categoryPendingDelete = nil
                Task {
                    do {
                        try await viewModel.softDeleteCategory(category)
                    } catch {
                        // errorMessage 已由 ViewModel 写入
                    }
                }
            }
            Button(L10n.Common.cancel, role: .cancel) {
                categoryPendingDelete = nil
            }
        }
        .alert(
            L10n.Common.notice.localized,
            isPresented: Binding(
                get: { deleteBlockedMessage != nil },
                set: { if $0 == false { deleteBlockedMessage = nil } }
            )
        ) {
            Button(L10n.Common.ok, role: .cancel) {
                deleteBlockedMessage = nil
            }
        } message: {
            if let deleteBlockedMessage {
                Text(deleteBlockedMessage)
            }
        }
    }

    // MARK: - Period chrome

    private var periodChrome: some View {
        HStack(spacing: 8) {
            // 与右侧粒度入口对称占位，保持中间日期居中
            granularityMenu
                .hidden()
                .accessibilityHidden(true)

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button {
                    viewModel.shiftPeriod(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(L10n.Ledger.previousPeriod.localized)

                Text(viewModel.periodTitle(locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Button {
                    viewModel.shiftPeriod(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(L10n.Ledger.nextPeriod.localized)
            }

            Spacer(minLength: 4)

            granularityMenu
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private var granularityMenu: some View {
        Menu {
            ForEach(LedgerReportPeriod.allCases) { period in
                Button {
                    viewModel.ledgerGranularity = period
                } label: {
                    HStack {
                        Text(granularityLabel(for: period))
                        if viewModel.ledgerGranularity == period {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(granularityLabel(for: viewModel.ledgerGranularity))
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemFill))
            .clipShape(Capsule())
        }
    }

    // MARK: - Sections

    private func categorySection(
        title: LocalizedStringResource,
        total: Double,
        type: LedgerEntryType,
        isExpanded: Binding<Bool>
    ) -> some View {
        let categories = viewModel.categories(for: type)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack {
                        Text(title)
                            .font(.headline)
                        Text(currencyText(total))
                            .font(.headline)
                            .foregroundStyle(type == .income ? Color.green : Color.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if allowsExpenseManagement {
                    Button {
                        manageCategoriesInitialType = type
                        isShowingCategoryManager = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Ledger.manageCategories.localized)
                }
            }

            if isExpanded.wrappedValue {
                if categories.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.Ledger.noCategories.localized, systemImage: "folder")
                    } description: {
                        Text(L10n.Ledger.noCategoriesHint.localized)
                    } actions: {
                        Button(L10n.Common.reload) {
                            LedgerWalletLoadLogger.step(
                                .reloadTapped,
                                source: "empty_ui",
                                householdId: viewModel.currentHouseholdIdValue,
                                detail: "type=\(type.rawValue)"
                            )
                            Task { await viewModel.loadLedgerData(force: true, source: "reload_button") }
                        }
                        if allowsExpenseManagement {
                            Button(L10n.Ledger.manageCategories.localized) {
                                manageCategoriesInitialType = type
                                isShowingCategoryManager = true
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .onAppear {
                        LedgerWalletLoadLogger.step(
                            .emptyUIShown,
                            source: "dashboard",
                            householdId: viewModel.currentHouseholdIdValue,
                            detail: "type=\(type.rawValue) loading=\(viewModel.isLoading) error=\(viewModel.errorMessage ?? "nil") cats=\(viewModel.categories.count)"
                        )
                    }
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(categories) { category in
                            LedgerCategoryCard(
                                name: category.name,
                                icon: category.icon,
                                amountText: currencyText(viewModel.amount(for: category.id, type: type)),
                                colorHex: category.colorHex
                            ) {
                                entryPrefill = ManualEntryPrefill(
                                    type: type,
                                    categoryId: category.id
                                )
                            }
                            .contextMenu {
                                if allowsExpenseManagement {
                                    Button(L10n.Ledger.editCategory.localized, systemImage: "pencil") {
                                        categoryPendingEdit = category
                                    }
                                    Button(L10n.Ledger.manageCategories.localized, systemImage: "folder.badge.gearshape") {
                                        manageCategoriesInitialType = type
                                        isShowingCategoryManager = true
                                    }
                                    Button(L10n.Ledger.deleteCategory.localized, systemImage: "trash", role: .destructive) {
                                        attemptDelete(category)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - FAB

    private var logEntryFAB: some View {
        Button {
            let defaultType: LedgerEntryType = allowsExpenseManagement ? .expense : .income
            entryPrefill = ManualEntryPrefill(type: defaultType, categoryId: nil)
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel(
            allowsExpenseManagement
                ? L10n.Ledger.logEntry.localized
                : L10n.Ledger.logIncome.localized
        )
    }

    // MARK: - Helpers

    private func granularityLabel(for period: LedgerReportPeriod) -> LocalizedStringResource {
        switch period {
        case .day: L10n.Common.day.localized
        case .week: L10n.Common.week.localized
        case .month: L10n.Common.month.localized
        case .year: L10n.Common.year.localized
        }
    }

    private func currencyText(_ value: Double) -> String {
        // 依赖 appSettings / exchangeRates，切换显示货币或汇率刷新时触发重绘
        _ = appSettings.ledgerDisplayCurrency
        _ = exchangeRates.fetchedAt
        return LedgerMoneyFormatter.string(
            value,
            currencyCode: viewModel.displayCurrencyCode,
            locale: locale
        )
    }

    private func attemptDelete(_ category: ExpenseCategory) {
        if viewModel.canDeleteCategory(category) {
            LedgerCategoryDeleteLogger.step(
                .confirmPresented,
                categoryId: category.id,
                categoryName: category.name,
                householdId: viewModel.currentHouseholdIdValue,
                detail: "source=dashboard_context_menu"
            )
            categoryPendingDelete = category
            isConfirmingCategoryDelete = true
        } else {
            LedgerCategoryDeleteLogger.step(
                .blockedHasTransactions,
                categoryId: category.id,
                categoryName: category.name,
                householdId: viewModel.currentHouseholdIdValue,
                detail: "source=dashboard_context_menu"
            )
            AnalyticsManager.log(event: .ledgerCategoryDeleteBlocked(reason: "has_linked_transactions"))
            deleteBlockedMessage = AppLocalized.string(
                L10n.Ledger.cannotDeleteCategoryWithEntries,
                locale: locale
            )
        }
    }
}

private struct ManualEntryPrefill: Identifiable {
    let id = UUID()
    let type: LedgerEntryType
    let categoryId: UUID?
}
