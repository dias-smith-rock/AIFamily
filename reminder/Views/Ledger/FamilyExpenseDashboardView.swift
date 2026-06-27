import SwiftUI

struct FamilyExpenseDashboardView: View {
    @ObservedObject var viewModel: FamilyLedgerViewModel
    @State private var isShowingManualEntry = false

    var body: some View {
        VStack(spacing: 0) {
            summaryStrip
            actionCapsules
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.expenseEntries.isEmpty {
                ContentUnavailableView {
                    Label(L10n.Ledger.noExpenseEntries.localized, systemImage: "tray")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.expenseEntries) { entry in
                        LedgerExpenseRow(
                            entry: entry,
                            payerLabel: viewModel.membershipDisplayName(for: entry.payerId)
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $isShowingManualEntry) {
            ManualExpenseEntrySheet(viewModel: viewModel)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            summaryTile(
                title: L10n.Ledger.monthlyExpense.localized,
                value: currencyText(viewModel.monthExpenseTotal),
                tint: .red
            )
            summaryTile(
                title: L10n.Ledger.monthlyIncome.localized,
                value: currencyText(viewModel.monthIncomeTotal),
                tint: .green
            )
            summaryTile(
                title: L10n.Ledger.monthlyNet.localized,
                value: currencyText(viewModel.monthNetTotal),
                tint: .primary
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func summaryTile(title: LocalizedStringResource, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
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

    private var actionCapsules: some View {
        HStack(spacing: 10) {
            LedgerActionCapsule(
                title: L10n.Ledger.aiReceipt.localized,
                systemImage: "camera",
                badge: L10n.Ledger.proFeature.localized,
                isEnabled: false
            ) {}

            LedgerActionCapsule(
                title: L10n.Ledger.voiceEntry.localized,
                systemImage: "mic",
                isEnabled: false
            ) {}

            LedgerActionCapsule(
                title: L10n.Ledger.manualEntry.localized,
                systemImage: "square.and.pencil",
                isEnabled: true
            ) {
                isShowingManualEntry = true
            }
        }
    }

    private func currencyText(_ value: Double) -> String {
        value.formatted(.currency(code: Locale.current.currency?.identifier ?? "CNY").precision(.fractionLength(0...2)))
    }
}

private struct LedgerExpenseRow: View {
    let entry: FamilyTask
    let payerLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(entry.expenseCategory ?? "📥")
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(payerLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(signedAmountText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(entry.isLedgerIncomeEntry ? .green : .primary)
                Text((entry.dueDate ?? entry.createdAt).formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var signedAmountText: String {
        let magnitude = entry.ledgerAmountDisplayMagnitude
        let formatted = magnitude.formatted(.number.precision(.fractionLength(0...2)))
        return entry.isLedgerIncomeEntry ? "+\(formatted)" : "-\(formatted)"
    }
}

private struct LedgerActionCapsule: View {
    let title: LocalizedStringResource
    let systemImage: String
    var badge: LocalizedStringResource? = nil
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                    if let badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.9))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -8)
                    }
                }
                Text(title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
