import SwiftUI

/// 某分类下的记账列表（从记一笔底部摘要进入）。
struct CategoryLedgerEntriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: FamilyLedgerViewModel
    @ObservedObject private var exchangeRates = ExchangeRateStore.shared

    let categoryId: UUID
    let categoryTitle: String

    @State private var selectedTransaction: LedgerTransaction?
    @State private var pendingDeleteId: UUID?
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        L10n.Ledger.noCategoryEntries.localized,
                        systemImage: "tray",
                        description: Text(categoryTitle)
                    )
                } else {
                    List {
                        ForEach(entries) { transaction in
                            entryRow(transaction)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTransaction = transaction
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteId = transaction.id
                                        isConfirmingDelete = true
                                    } label: {
                                        Label {
                                            Text(L10n.Ledger.deleteEntry.localized)
                                        } icon: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(L10n.Ledger.categoryEntries.localized)
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
                    guard let pendingDeleteId else { return }
                    let id = pendingDeleteId
                    self.pendingDeleteId = nil
                    Task { await deleteEntry(id) }
                }
                Button(L10n.Common.cancel, role: .cancel) {
                    pendingDeleteId = nil
                }
            } message: {
                Text(L10n.Ledger.deleteEntryMessage.localized)
            }
            .sheet(item: $selectedTransaction) { transaction in
                LedgerTransactionDetailSheet(
                    viewModel: viewModel,
                    transactionId: transaction.id
                )
            }
        }
    }

    private var entries: [LedgerTransaction] {
        _ = exchangeRates.fetchedAt
        return viewModel.transactions(forCategoryId: categoryId)
    }

    @ViewBuilder
    private func entryRow(_ transaction: LedgerTransaction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.note?.nilIfEmpty ?? transaction.categoryNameSnapshot)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(formattedTime(transaction.transactionTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if transaction.tagSnapshots.isEmpty == false {
                    Text(transaction.tagSnapshots.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(moneyText(for: transaction))
                .font(.body.weight(.semibold))
                .foregroundStyle(transaction.type == .expense ? Color.primary : Color.green)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func moneyText(for transaction: LedgerTransaction) -> String {
        LedgerMoneyFormatter.string(
            viewModel.convertedAmount(for: transaction),
            currencyCode: viewModel.displayCurrencyCode,
            locale: locale
        )
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        return formatter.string(from: date)
    }

    private func deleteEntry(_ id: UUID) async {
        do {
            try await viewModel.deleteTransaction(id: id)
            if selectedTransaction?.id == id {
                selectedTransaction = nil
            }
        } catch {
            // errorMessage on viewModel
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
