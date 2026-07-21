import SwiftUI
import Charts

struct LedgerReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: FamilyLedgerViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    periodPicker
                    filterPickers
                    totalsRow
                    categoryChartSection
                }
                .padding(16)
            }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle(L10n.Ledger.reports.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                }
            }
        }
    }

    private var periodPicker: some View {
        Picker("", selection: $viewModel.reportPeriod) {
            Text(L10n.Ledger.periodDay.localized).tag(LedgerReportPeriod.day)
            Text(L10n.Ledger.periodWeek.localized).tag(LedgerReportPeriod.week)
            Text(L10n.Ledger.periodMonth.localized).tag(LedgerReportPeriod.month)
            Text(L10n.Ledger.periodYear.localized).tag(LedgerReportPeriod.year)
        }
        .pickerStyle(.segmented)
    }

    private var filterPickers: some View {
        VStack(spacing: 12) {
            Picker(L10n.Ledger.payer.localized, selection: $viewModel.reportPayerFilterId) {
                Text(L10n.Ledger.allPayers.localized).tag(UUID?.none)
                ForEach(viewModel.familyProfiles) { profile in
                    Text(profile.displayName).tag(Optional(profile.id))
                }
            }

            Picker(L10n.Ledger.forWhom.localized, selection: $viewModel.reportTargetFilterId) {
                Text(L10n.Ledger.allTargets.localized).tag(UUID?.none)
                ForEach(viewModel.familyProfiles) { profile in
                    Text(profile.displayName).tag(Optional(profile.id))
                }
            }
        }
    }

    private var totalsRow: some View {
        HStack(spacing: 12) {
            reportTile(
                title: L10n.Ledger.expense.localized,
                value: viewModel.reportExpenseTotal,
                tint: .red
            )
            reportTile(
                title: L10n.Ledger.income.localized,
                value: viewModel.reportIncomeTotal,
                tint: .green
            )
            reportTile(
                title: L10n.Ledger.monthlyNet.localized,
                value: viewModel.reportNetTotal,
                tint: .primary
            )
        }
    }

    private func reportTile(title: LocalizedStringResource, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.formatted(.number.precision(.fractionLength(0...2))))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var categoryChartSection: some View {
        let breakdown = viewModel.categoryExpenseBreakdown
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Ledger.categoryBreakdown.localized)
                .font(.headline)

            if breakdown.isEmpty {
                Text(L10n.Ledger.noExpenseEntries.localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                Chart(breakdown, id: \.name) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Category", item.name))
                }
                .frame(height: 220)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(breakdown, id: \.name) { item in
                        HStack {
                            Text("\(item.icon ?? "🏷️") \(item.name)")
                                .font(.subheadline)
                            Spacer()
                            Text(item.amount.formatted(.number.precision(.fractionLength(0...2))))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
