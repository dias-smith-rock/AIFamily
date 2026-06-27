import SwiftUI

struct ManualExpenseEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @ObservedObject var viewModel: FamilyLedgerViewModel

    @State private var isIncome = false
    @State private var amountText = ""
    @State private var titleText = ""
    @State private var noteText = ""
    @State private var selectedCategoryId: UUID?
    @State private var selectedPayerId: UUID?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $isIncome) {
                        Text(L10n.Ledger.expense.localized).tag(false)
                        Text(L10n.Ledger.income.localized).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField(AppLocalized.string(L10n.Ledger.amount, locale: locale), text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField(AppLocalized.string(L10n.Ledger.titleField, locale: locale), text: $titleText)
                    TextField(AppLocalized.string(L10n.Ledger.note, locale: locale), text: $noteText, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Picker(L10n.Ledger.category.localized, selection: categoryBinding) {
                        ForEach(viewModel.categories) { category in
                            Text(category.displayLabel).tag(category.id)
                        }
                    }

                    Picker(L10n.Ledger.payer.localized, selection: payerBinding) {
                        ForEach(viewModel.householdMembers.filter { $0.isActiveMembership() }) { member in
                            Text(viewModel.membershipDisplayName(for: member.id))
                                .tag(member.id)
                        }
                    }
                }
            }
            .navigationTitle(L10n.Ledger.manualEntry.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Ledger.saveEntry.localized) {
                        Task { await saveEntry() }
                    }
                    .disabled(canSave == false || isSaving)
                }
            }
            .onAppear(perform: applyDefaults)
        }
    }

    private var categoryBinding: Binding<UUID> {
        Binding(
            get: { selectedCategoryId ?? viewModel.categories.first?.id ?? UUID() },
            set: { selectedCategoryId = $0 }
        )
    }

    private var payerBinding: Binding<UUID> {
        Binding(
            get: { selectedPayerId ?? appRouter.selectedMembershipId ?? viewModel.householdMembers.first?.id ?? UUID() },
            set: { selectedPayerId = $0 }
        )
    }

    private var canSave: Bool {
        parsedAmount != nil && (parsedAmount ?? 0) > 0
    }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func applyDefaults() {
        selectedCategoryId = viewModel.categories.first?.id
        selectedPayerId = appRouter.selectedMembershipId ?? viewModel.householdMembers.first?.id
    }

    private func saveEntry() async {
        guard let amount = parsedAmount,
              let category = viewModel.categories.first(where: { $0.id == (selectedCategoryId ?? viewModel.categories.first?.id) }),
              let payerId = selectedPayerId ?? appRouter.selectedMembershipId,
              let creatorId = appRouter.selectedMembershipId else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.createExpenseEntry(
                isIncome: isIncome,
                amount: amount,
                title: titleText,
                note: noteText,
                categoryLabel: category.displayLabel,
                payerMembershipId: payerId,
                creatorMembershipId: creatorId
            )
            dismiss()
        } catch {
            // ViewModel surfaces via errorMessage if needed
        }
    }
}
