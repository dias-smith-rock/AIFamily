import SwiftUI

struct ManualExpenseEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @ObservedObject var viewModel: FamilyLedgerViewModel
    @ObservedObject private var exchangeRates = ExchangeRateStore.shared
    @StateObject private var familyViewModel = AppViewModels.makeFamilyViewModel()

    private let prefillType: LedgerEntryType
    private let prefillCategoryId: UUID?
    private let locksToIncome: Bool
    private let editingTransaction: LedgerTransaction?

    @State private var entryType: LedgerEntryType
    @State private var amountText = ""
    @State private var currency: String
    @State private var transactionTime = Date()
    @State private var selectedCategoryId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedPayerIds: Set<UUID> = []
    @State private var selectedTargetIds: Set<UUID> = []
    @State private var selectedVisibleIds: Set<UUID> = []
    @State private var noteText = ""
    @State private var isSaving = false
    @State private var isPresentingCreateLocalProfile = false
    @State private var isShowingCategoryEntries = false

    private let currencies = LedgerCurrency.allCodes

    private var isEditing: Bool { editingTransaction != nil }

    init(
        viewModel: FamilyLedgerViewModel,
        prefillType: LedgerEntryType = .expense,
        prefillCategoryId: UUID? = nil,
        locksToIncome: Bool = false,
        editingTransaction: LedgerTransaction? = nil
    ) {
        self.viewModel = viewModel
        self.editingTransaction = editingTransaction
        if let editingTransaction {
            self.prefillType = editingTransaction.type
            self.prefillCategoryId = editingTransaction.categoryId
            self.locksToIncome = locksToIncome || editingTransaction.type == .income
            _entryType = State(initialValue: editingTransaction.type)
            _amountText = State(initialValue: Self.amountFieldText(editingTransaction.amount))
            _currency = State(initialValue: editingTransaction.currency)
            _transactionTime = State(initialValue: editingTransaction.transactionTime)
            _selectedCategoryId = State(initialValue: editingTransaction.categoryId)
            _selectedPayerIds = State(initialValue: Set(editingTransaction.payerIds))
            _selectedTargetIds = State(initialValue: Set(editingTransaction.targetMemberIds))
            _selectedVisibleIds = State(initialValue: Set(editingTransaction.visibleMemberIds))
            _noteText = State(initialValue: editingTransaction.note ?? "")
        } else {
            self.prefillType = locksToIncome ? .income : prefillType
            self.prefillCategoryId = prefillCategoryId
            self.locksToIncome = locksToIncome
            _entryType = State(initialValue: locksToIncome ? .income : prefillType)
            _currency = State(initialValue: AppSettingsManager.shared.ledgerDisplayCurrency)
        }
    }

    /// 当前用户若仍是「新成员」占位，记一笔页统一显示「我」。
    private func memberLabel(for profile: FamilyProfile) -> String {
        let label = profile.displayName
        guard profile.id == currentCreatorProfileId else { return label }
        if FamilyProfile.isNewMemberPlaceholder(label) {
            return AppLocalized.string(L10n.Common.me, locale: locale)
        }
        return label
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isEditing == false, selectedCategoryId != nil {
                    categoryEntriesSummaryButton
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

                if locksToIncome == false && isEditing == false {
                    Picker("", selection: $entryType) {
                        Text(L10n.Ledger.expense.localized).tag(LedgerEntryType.expense)
                        Text(L10n.Ledger.income.localized).tag(LedgerEntryType.income)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 0)
                    .onChange(of: entryType) { _, _ in
                        selectedCategoryId = viewModel.categories(for: entryType).first?.id
                        selectedTagIds = []
                    }
                }

                Form {
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
                                Text(category.localizedDisplayLabel(locale: locale)).tag(category.id)
                            }
                        }
                        .onChange(of: selectedCategoryId) { _, _ in
                            selectedTagIds = []
                        }

                        if availableTags.isEmpty == false {
                            LedgerTagCapsuleFlow(spacing: 8) {
                                ForEach(availableTags) { tag in
                                    selectableCapsule(
                                        title: tag.localizedName(locale: locale),
                                        isSelected: selectedTagIds.contains(tag.id)
                                    ) {
                                        toggleTag(tag.id)
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        }
                    }

                    Section {
                        if selectableProfiles.isEmpty == false {
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.Ledger.payer.localized)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    LedgerTagCapsuleFlow(spacing: 8) {
                                        ForEach(selectableProfiles) { profile in
                                            selectableCapsule(
                                                title: memberLabel(for: profile),
                                                isSelected: selectedPayerIds.contains(profile.id)
                                            ) {
                                                togglePayer(profile.id)
                                            }
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.Ledger.beneficiaries.localized)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    LedgerTagCapsuleFlow(spacing: 8) {
                                        ForEach(selectableProfiles) { profile in
                                            selectableCapsule(
                                                title: memberLabel(for: profile),
                                                isSelected: selectedTargetIds.contains(profile.id)
                                            ) {
                                                toggleTarget(profile.id)
                                            }
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.Ledger.visibility.localized)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    LedgerTagCapsuleFlow(spacing: 8) {
                                        ForEach(selectableProfiles) { profile in
                                            selectableCapsule(
                                                title: memberLabel(for: profile),
                                                isSelected: selectedVisibleIds.contains(profile.id)
                                            ) {
                                                toggleVisible(profile.id)
                                            }
                                        }
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        }
                    } header: {
                        Text(L10n.Ledger.forWhom.localized)
                    } footer: {
                        VStack(alignment: .leading, spacing: 8) {
                            if selectableProfiles.isEmpty {
                                Text(L10n.Ledger.noMembersHint.localized)
                            }
                            if canCreateVirtualProfile {
                                Button {
                                    prepareFamilyContext()
                                    isPresentingCreateLocalProfile = true
                                } label: {
                                    Label(L10n.Ledger.addMember.localized, systemImage: "person.badge.plus")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .contentMargins(.top, 4, for: .scrollContent)
                .listSectionSpacing(12)
            }
            .navigationTitle(navigationTitle)
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
            .task {
                await viewModel.loadRoster()
                viewModel.setViewerContext(
                    membershipId: appRouter.selectedMembershipId,
                    fallbackProfileId: appRouter.selectedProfileId
                )
                applyDefaults()
            }
            .fullScreenCover(isPresented: $isPresentingCreateLocalProfile) {
                ProfileEditView(
                    mode: .createLocalProfile,
                    householdId: appRouter.selectedHouseholdId,
                    canEdit: canCreateVirtualProfile,
                    uploadAvatar: { data, profileId in
                        await familyViewModel.uploadAvatar(data: data, profileId: profileId)
                    },
                    onSave: { householdId, draft in
                        let failure = await familyViewModel.createLocalProfile(
                            householdId: householdId,
                            draft: draft,
                            hasPremiumAccess: appRouter.hasPremiumAccess
                        )
                        if failure == nil {
                            await viewModel.loadRoster()
                            if let me = currentCreatorProfileId {
                                selectedPayerIds.insert(me)
                            }
                        }
                        return failure
                    }
                )
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
            }
            .sheet(isPresented: $isShowingCategoryEntries) {
                if let selectedCategoryId {
                    CategoryLedgerEntriesSheet(
                        viewModel: viewModel,
                        categoryId: selectedCategoryId,
                        categoryTitle: selectedCategory?.localizedDisplayLabel(locale: locale) ?? ""
                    )
                    .environment(\.locale, appSettings.appLocale)
                    .environment(\.layoutDirection, appSettings.layoutDirection)
                }
            }
        }
    }

    // MARK: - Capsules

    @ViewBuilder
    private var categoryEntriesSummaryButton: some View {
        Button {
            isShowingCategoryEntries = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(categoryEntriesSummaryTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let category = selectedCategory {
                        Text(category.localizedDisplayLabel(locale: locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectableCapsule(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleTag(_ id: UUID) {
        if selectedTagIds.contains(id) {
            selectedTagIds.remove(id)
        } else {
            selectedTagIds.insert(id)
        }
    }

    private func togglePayer(_ id: UUID) {
        if selectedPayerIds.contains(id) {
            selectedPayerIds.remove(id)
        } else {
            selectedPayerIds.insert(id)
        }
    }

    private func toggleTarget(_ id: UUID) {
        if selectedTargetIds.contains(id) {
            selectedTargetIds.remove(id)
        } else {
            selectedTargetIds.insert(id)
        }
    }

    private func toggleVisible(_ id: UUID) {
        // Me 为必选，不可取消
        if id == currentCreatorProfileId {
            selectedVisibleIds.insert(id)
            return
        }
        if selectedVisibleIds.contains(id) {
            selectedVisibleIds.remove(id)
        } else {
            selectedVisibleIds.insert(id)
        }
    }

    // MARK: - Bindings / helpers

    private var navigationTitle: LocalizedStringResource {
        if isEditing {
            return L10n.Ledger.editEntry.localized
        }
        return locksToIncome
            ? L10n.Ledger.logIncome.localized
            : L10n.Ledger.manualEntry.localized
    }

    private var categoryEntriesSummaryTitle: String {
        _ = exchangeRates.fetchedAt
        guard let selectedCategoryId else { return "" }
        let count = viewModel.entryCount(forCategoryId: selectedCategoryId)
        let total = LedgerMoneyFormatter.string(
            viewModel.totalAmount(forCategoryId: selectedCategoryId),
            currencyCode: viewModel.displayCurrencyCode,
            locale: locale
        )
        return L10n.Ledger.categoryEntriesSummary.formatted(locale: locale, count, total)
    }

    /// 垫付人 / 受益人候选：保证当前登录成员的 profile 一定在列表中。
    private var selectableProfiles: [FamilyProfile] {
        var profiles = viewModel.familyProfiles
        guard let profileId = currentCreatorProfileId,
              profiles.contains(where: { $0.id == profileId }) == false else {
            return profiles
        }

        if let membership = viewModel.householdMembers.first(where: {
            $0.profileId == profileId || $0.id == appRouter.selectedMembershipId
        }) {
            let related = viewModel.householdMembers.filter {
                $0.profileId == profileId
                    || ($0.userId != nil && $0.userId == membership.userId)
            }
            let nickname = membership.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fallbackName: String = {
                if nickname.isEmpty == false,
                   FamilyProfile.isNewMemberPlaceholder(StoredDisplayNameResolver.selfName(nickname, locale: locale)) == false {
                    return nickname
                }
                return AppLocalized.string(L10n.Common.me, locale: locale)
            }()
            profiles.insert(
                FamilyProfile.syntheticPlaceholder(
                    profileId: profileId,
                    householdId: membership.householdId,
                    userId: membership.userId,
                    name: fallbackName,
                    memberships: related.isEmpty ? [membership] : related
                ),
                at: 0
            )
        } else {
            profiles.insert(
                FamilyProfile.syntheticPlaceholder(
                    profileId: profileId,
                    householdId: viewModel.currentHouseholdIdValue,
                    userId: nil,
                    name: AppLocalized.string(L10n.Common.me, locale: locale),
                    memberships: []
                ),
                at: 0
            )
        }
        return profiles
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

    private var canSave: Bool {
        guard let amount = parsedAmount, amount > 0 else { return false }
        return selectedCategory != nil
            && currentCreatorProfileId != nil
            && selectedPayerIds.isEmpty == false
            && selectedVisibleIds.isEmpty == false
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

    /// 有账号的正式成员可新建无账号档案。
    private var canCreateVirtualProfile: Bool {
        guard let selectedMembershipId = appRouter.selectedMembershipId else { return false }
        guard let currentMembership = viewModel.householdMembers.first(where: { $0.id == selectedMembershipId }) else {
            return false
        }
        return currentMembership.userId != nil
    }

    private func prepareFamilyContext() {
        familyViewModel.setHouseholdContext(appRouter.selectedHouseholdId)
        familyViewModel.setMembershipContext(appRouter.selectedMembershipId)
    }

    private func applyDefaults() {
        if let editing = editingTransaction {
            entryType = editing.type
            selectedCategoryId = editing.categoryId
            selectedPayerIds = Set(editing.payerIds)
            selectedTargetIds = Set(editing.targetMemberIds)
            selectedVisibleIds = Set(editing.visibleMemberIds)
            if let me = currentCreatorProfileId {
                selectedVisibleIds.insert(me)
            }
            // 用标签名快照反查当前分类下的 tag id
            let names = Set(editing.tagSnapshots)
            selectedTagIds = Set(
                availableTags.filter { names.contains($0.name) }.map(\.id)
            )
            return
        }

        entryType = prefillType
        let available = viewModel.categories(for: entryType)
        if let prefillCategoryId,
           available.contains(where: { $0.id == prefillCategoryId }) {
            selectedCategoryId = prefillCategoryId
        } else if selectedCategoryId == nil || available.contains(where: { $0.id == selectedCategoryId }) == false {
            selectedCategoryId = available.first?.id
        }
        if selectedPayerIds.isEmpty {
            if let me = currentCreatorProfileId {
                selectedPayerIds.insert(me)
            } else if let first = selectableProfiles.first?.id {
                selectedPayerIds.insert(first)
            }
        }
        if selectedVisibleIds.isEmpty {
            selectedVisibleIds = defaultVisibleProfileIds
        }
        if let me = currentCreatorProfileId {
            selectedVisibleIds.insert(me)
        }
    }

    /// 默认可见：组织内 creator / admin 对应的 profile；始终包含 Me。
    private var defaultVisibleProfileIds: Set<UUID> {
        var ids = Set(
            viewModel.householdMembers.compactMap { membership -> UUID? in
                guard let role = membership.parsedRole,
                      role == .creator || role == .admin,
                      let profileId = membership.profileId else {
                    return nil
                }
                return profileId
            }
        )
        if let me = currentCreatorProfileId {
            ids.insert(me)
        }
        return ids
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
        var visibleIds = selectedVisibleIds
        visibleIds.insert(creatorId)
        let draft = LedgerTransactionDraft(
            householdId: householdId,
            type: entryType,
            amount: amount,
            currency: currency,
            transactionTime: transactionTime,
            category: category,
            selectedTags: selectedTags,
            payerIds: Array(selectedPayerIds),
            targetMemberIds: Array(selectedTargetIds),
            visibleMemberIds: Array(visibleIds),
            note: noteText,
            creatorProfileId: editingTransaction?.creatorId ?? creatorId
        )

        do {
            if let editingTransaction {
                try await viewModel.updateTransaction(id: editingTransaction.id, draft: draft)
            } else {
                try await viewModel.createTransaction(draft)
                if appRouter.isAnonymousUser {
                    AnonymousBindPromptStore.schedule()
                }
            }
            dismiss()
        } catch {
            // errorMessage surfaced on dashboard reload if needed
        }
    }

    private static func amountFieldText(_ amount: Double) -> String {
        if amount.rounded() == amount {
            return String(Int(amount))
        }
        return String(format: "%g", amount)
    }
}
