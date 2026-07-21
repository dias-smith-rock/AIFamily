import SwiftUI

struct FamilyExpenseDashboardView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: FamilyLedgerViewModel

    /// `false`：普通成员仅进账（收入网格），不展示支出/报表/分类管理。
    var allowsExpenseManagement: Bool = true

    @State private var expenseExpanded = true
    @State private var incomeExpanded = true
    @State private var entryPrefill: ManualEntryPrefill?
    @State private var isShowingCategoryManager = false
    @State private var isShowingReports = false

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
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.loadInitialData(force: true)
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
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
            ManageCategoriesSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingReports) {
            LedgerReportsView(viewModel: viewModel)
        }
    }

    // MARK: - Period chrome

    private var periodChrome: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.shiftPeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(L10n.Ledger.previousPeriod.localized)

            Spacer(minLength: 4)

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
            }

            Text(viewModel.periodTitle(locale: locale))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            Button {
                viewModel.shiftPeriod(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(L10n.Ledger.nextPeriod.localized)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
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
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                if categories.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.Ledger.noCategories.localized, systemImage: "folder")
                    } description: {
                        Text(L10n.Ledger.noCategoriesHint.localized)
                    } actions: {
                        if allowsExpenseManagement {
                            Button(L10n.Ledger.manageCategories.localized) {
                                isShowingCategoryManager = true
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(alignment: .center) {
            if allowsExpenseManagement {
                Button {
                    isShowingCategoryManager = true
                } label: {
                    Image(systemName: "lightbulb")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L10n.Ledger.manageCategories.localized)
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Button {
                let defaultType: LedgerEntryType = allowsExpenseManagement ? .expense : .income
                entryPrefill = ManualEntryPrefill(type: defaultType, categoryId: nil)
            } label: {
                Label(
                    allowsExpenseManagement
                        ? L10n.Ledger.logEntry.localized
                        : L10n.Ledger.logIncome.localized,
                    systemImage: "plus"
                )
                .font(.headline)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
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
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct ManualEntryPrefill: Identifiable {
    let id = UUID()
    let type: LedgerEntryType
    let categoryId: UUID?
}
