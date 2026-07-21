import SwiftUI

/// 单笔记账详情：查看、编辑、删除。
struct LedgerTransactionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appSettings: AppSettingsManager
    @ObservedObject var viewModel: FamilyLedgerViewModel

    let transactionId: UUID

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            Group {
                if let transaction {
                    Form {
                        Section {
                            detailRow(
                                title: L10n.Ledger.amount.localized,
                                value: moneyText(for: transaction),
                                valueWeight: .semibold
                            )
                            detailRow(
                                title: L10n.Ledger.currency.localized,
                                value: transaction.currency
                            )
                            detailRow(
                                title: L10n.Ledger.transactionTime.localized,
                                value: formattedTime(transaction.transactionTime)
                            )
                            if let note = transaction.note, note.isEmpty == false {
                                detailRow(
                                    title: L10n.Ledger.note.localized,
                                    value: note
                                )
                            }
                        }

                        Section {
                            detailRow(
                                title: L10n.Ledger.category.localized,
                                value: "\(transaction.categoryIconSnapshot ?? "") \(transaction.categoryNameSnapshot)"
                                    .trimmingCharacters(in: .whitespaces)
                            )
                            if transaction.tagSnapshots.isEmpty == false {
                                detailRow(
                                    title: L10n.Ledger.tags.localized,
                                    value: transaction.tagSnapshots.joined(separator: ", ")
                                )
                            }
                        }

                        Section {
                            detailRow(
                                title: L10n.Ledger.payer.localized,
                                value: memberNames(transaction.payerIds)
                            )
                            detailRow(
                                title: L10n.Ledger.beneficiaries.localized,
                                value: memberNames(transaction.targetMemberIds)
                            )
                            detailRow(
                                title: L10n.Ledger.visibility.localized,
                                value: visibilityDisplay(for: transaction)
                            )
                        } header: {
                            Text(L10n.Ledger.forWhom.localized)
                        }

                        Section {
                            Button(L10n.Ledger.editEntry.localized) {
                                isEditing = true
                            }
                            Button(L10n.Ledger.deleteEntry.localized, role: .destructive) {
                                isConfirmingDelete = true
                            }
                            .disabled(isDeleting)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        L10n.Ledger.noCategoryEntries.localized,
                        systemImage: "trash"
                    )
                }
            }
            .navigationTitle(L10n.Ledger.entryDetail.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                }
            }
            .alert(
                L10n.Ledger.deleteEntry.localized,
                isPresented: $isConfirmingDelete
            ) {
                Button(L10n.Ledger.deleteEntry.localized, role: .destructive) {
                    Task { await deleteEntry() }
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                Text(L10n.Ledger.deleteEntryMessage.localized)
            }
            .sheet(isPresented: $isEditing) {
                if let transaction {
                    ManualExpenseEntrySheet(
                        viewModel: viewModel,
                        editingTransaction: transaction
                    )
                    .environment(\.locale, appSettings.appLocale)
                    .environment(\.layoutDirection, appSettings.layoutDirection)
                }
            }
        }
    }

    private var transaction: LedgerTransaction? {
        viewModel.transactions.first { $0.id == transactionId }
    }

    @ViewBuilder
    private func detailRow(
        title: LocalizedStringResource,
        value: String,
        valueWeight: Font.Weight = .regular
    ) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(valueWeight)
                .multilineTextAlignment(.trailing)
        }
    }

    private func moneyText(for transaction: LedgerTransaction) -> String {
        let converted = LedgerMoneyFormatter.string(
            viewModel.convertedAmount(for: transaction),
            currencyCode: viewModel.displayCurrencyCode,
            locale: locale
        )
        let original = LedgerMoneyFormatter.string(
            transaction.amount,
            currencyCode: transaction.currency,
            locale: locale
        )
        if transaction.currency == viewModel.displayCurrencyCode {
            return converted
        }
        return "\(converted) (\(original))"
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMd HH:mm")
        return formatter.string(from: date)
    }

    private func memberNames(_ ids: [UUID]) -> String {
        guard ids.isEmpty == false else { return "—" }
        return ids.map { viewModel.profileDisplayName(for: $0) }.joined(separator: ", ")
    }

    private func visibilityDisplay(for transaction: LedgerTransaction) -> String {
        if transaction.visibleMemberIds.isEmpty {
            return AppLocalized.string(L10n.Ledger.visibilityEveryoneWithAccess, locale: locale)
        }
        return memberNames(transaction.visibleMemberIds)
    }

    private func deleteEntry() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await viewModel.deleteTransaction(id: transactionId)
            dismiss()
        } catch {
            // errorMessage on viewModel
        }
    }
}
