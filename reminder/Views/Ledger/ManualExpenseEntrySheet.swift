import SwiftUI

struct ManualExpenseEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @ObservedObject var viewModel: FamilyLedgerViewModel

    private let prefillType: LedgerEntryType
    private let prefillCategoryId: UUID?
    private let locksToIncome: Bool

    @State private var entryType: LedgerEntryType
    @State private var amountText = ""
    @State private var currency = "HKD"
    @State private var transactionTime = Date()
    @State private var selectedCategoryId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedPayerId: UUID?
    @State private var selectedTargetIds: Set<UUID> = []
    @State private var noteText = ""
    @State private var isSaving = false

    private let currencies = ["HKD", "CNY", "USD", "EUR", "JPY"]

    init(
        viewModel: FamilyLedgerViewModel,
        prefillType: LedgerEntryType = .expense,
        prefillCategoryId: UUID? = nil,
        locksToIncome: Bool = false
    ) {
        self.viewModel = viewModel
        self.prefillType = locksToIncome ? .income : prefillType
        self.prefillCategoryId = prefillCategoryId
        self.locksToIncome = locksToIncome
        _entryType = State(initialValue: locksToIncome ? .income : prefillType)
    }

    var body: some View {
        NavigationStack {
            Form {
                if locksToIncome == false {
                    Section {
                        Picker("", selection: $entryType) {
                            Text(L10n.Ledger.expense.localized).tag(LedgerEntryType.expense)
                            Text(L10n.Ledger.income.localized).tag(LedgerEntryType.income)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .onChange(of: entryType) { _, _ in
                            selectedCategoryId = viewModel.categories(for: entryType).first?.id
                            selectedTagIds = []
                        }
                    }
                }

                Section {
                    TextField(AppLocalized.string(L10n.Ledger.amount, locale: locale), text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker(L10n.Ledger.currency.localized, selection: $currency) {
                        ForEach(currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    DatePicker(
                        L10n.Ledger.transactionTime.localized,
                        selection: $transactionTime,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    TextField(AppLocalized.string(L10n.Ledger.note, locale: locale), text: $noteText, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Picker(L10n.Ledger.category.localized, selection: categoryBinding) {
                        ForEach(viewModel.categories(for: entryType)) { category in
                            Text(category.displayLabel).tag(category.id)
                        }
                    }
                    .onChange(of: selectedCategoryId) { _, _ in
                        selectedTagIds = []
                    }

                    if availableTags.isEmpty == false {
                        ForEach(availableTags) { tag in
                            Toggle(isOn: tagBinding(tag.id)) {
                                Text(tag.name)
                            }
                        }
                    }
                }

                Section {
                    Picker(L10n.Ledger.payer.localized, selection: payerBinding) {
                        Text(L10n.Ledger.noneOptional.localized).tag(UUID?.none)
                        ForEach(viewModel.familyProfiles) { profile in
                            Text(profile.displayName).tag(Optional(profile.id))
                        }
                    }

                    ForEach(viewModel.familyProfiles) { profile in
                        Toggle(isOn: targetBinding(profile.id)) {
                            Text(profile.displayName)
                        }
                    }
                } header: {
                    Text(L10n.Ledger.forWhom.localized)
                }
            }
            .navigationTitle(
                locksToIncome
                    ? L10n.Ledger.logIncome.localized
                    : L10n.Ledger.manualEntry.localized
            )
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

    private var availableTags: [CategoryTag] {
        guard let selectedCategoryId else { return [] }
        return viewModel.tags(for: selectedCategoryId)
    }

    private var categoryBinding: Binding<UUID> {
        Binding(
            get: { selectedCategoryId ?? viewModel.categories(for: entryType).first?.id ?? UUID() },
            set: { selectedCategoryId = $0 }
        )
    }

    private var payerBinding: Binding<UUID?> {
        Binding(
            get: { selectedPayerId },
            set: { selectedPayerId = $0 }
        )
    }

    private func tagBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedTagIds.contains(id) },
            set: { isOn in
                if isOn { selectedTagIds.insert(id) } else { selectedTagIds.remove(id) }
            }
        )
    }

    private func targetBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedTargetIds.contains(id) },
            set: { isOn in
                if isOn { selectedTargetIds.insert(id) } else { selectedTargetIds.remove(id) }
            }
        )
    }

    private var canSave: Bool {
        guard let amount = parsedAmount, amount > 0 else { return false }
        return selectedCategory != nil && currentCreatorProfileId != nil
    }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var selectedCategory: ExpenseCategory? {
        viewModel.categories(for: entryType).first { $0.id == selectedCategoryId }
    }

    private var currentCreatorProfileId: UUID? {
        if let membershipId = appRouter.selectedMembershipId,
           let membership = viewModel.householdMembers.first(where: { $0.id == membershipId }),
           let profileId = membership.profileId {
            return profileId
        }
        return appRouter.selectedProfileId
    }

    private func applyDefaults() {
        entryType = prefillType
        let available = viewModel.categories(for: entryType)
        if let prefillCategoryId,
           available.contains(where: { $0.id == prefillCategoryId }) {
            selectedCategoryId = prefillCategoryId
        } else {
            selectedCategoryId = available.first?.id
        }
        selectedPayerId = currentCreatorProfileId
    }

    private func saveEntry() async {
        guard let amount = parsedAmount,
              let category = selectedCategory,
              let creatorId = currentCreatorProfileId,
              let householdId = viewModel.currentHouseholdIdValue else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        let selectedTags = availableTags.filter { selectedTagIds.contains($0.id) }
        let draft = LedgerTransactionDraft(
            householdId: householdId,
            type: entryType,
            amount: amount,
            currency: currency,
            transactionTime: transactionTime,
            category: category,
            selectedTags: selectedTags,
            payerId: selectedPayerId,
            targetMemberIds: Array(selectedTargetIds),
            note: noteText,
            creatorProfileId: creatorId
        )

        do {
            try await viewModel.createTransaction(draft)
            dismiss()
        } catch {
            // errorMessage surfaced on dashboard reload if needed
        }
    }
}
