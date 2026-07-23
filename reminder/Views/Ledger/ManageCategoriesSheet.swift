import SwiftUI

struct ManageCategoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: FamilyLedgerViewModel

    @State private var manageType: LedgerEntryType
    @State private var categoryPendingDelete: ExpenseCategory?
    @State private var isConfirmingCategoryDelete = false
    @State private var categoryPendingEdit: ExpenseCategory?
    @State private var isShowingCreateCategory = false
    @State private var deleteBlockedMessage: String?
    @State private var isSortingCategories = false

    init(viewModel: FamilyLedgerViewModel, initialType: LedgerEntryType = .expense) {
        self.viewModel = viewModel
        _manageType = State(initialValue: initialType)
    }

    private var managedCategories: [ExpenseCategory] {
        viewModel.categories(for: manageType)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                List {
                    Section {
                        Picker("", selection: $manageType) {
                            Text(L10n.Ledger.expense.localized).tag(LedgerEntryType.expense)
                            Text(L10n.Ledger.income.localized).tag(LedgerEntryType.income)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .disabled(isSortingCategories)
                    }

                    Section {
                        ForEach(managedCategories) { category in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(category.localizedDisplayLabel(locale: locale))
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                    if isSortingCategories == false {
                                        Button {
                                            categoryPendingEdit = category
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(L10n.Ledger.editCategory.localized)

                                        Button(role: .destructive) {
                                            attemptDelete(category)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(L10n.Ledger.deleteCategory.localized)
                                    }
                                }

                                let tags = viewModel.tags(for: category.id)
                                if tags.isEmpty == false {
                                    LedgerTagCapsuleFlow(spacing: 8) {
                                        ForEach(tags) { tag in
                                            Text(tag.localizedName(locale: locale))
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                                .fixedSize(horizontal: true, vertical: false)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.secondarySystemFill))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove { indexSet, destination in
                            guard isSortingCategories else { return }
                            viewModel.moveCategories(
                                for: manageType,
                                fromOffsets: indexSet,
                                toOffset: destination
                            )
                        }
                    } header: {
                        categoriesSectionHeader
                    }
                }
                .contentMargins(.bottom, 88, for: .scrollContent)
                .environment(\.editMode, .constant(isSortingCategories ? .active : .inactive))

                if isSortingCategories == false {
                    Button {
                        isShowingCreateCategory = true
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
                    .accessibilityLabel(L10n.Ledger.addCategory.localized)
                }
            }
            .navigationTitle(L10n.Ledger.manageCategories.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                }
            }
            .onChange(of: manageType) { _, _ in
                isSortingCategories = false
            }
            .sheet(item: $categoryPendingEdit) { category in
                EditCategorySheet(viewModel: viewModel, category: category)
            }
            .sheet(isPresented: $isShowingCreateCategory) {
                CreateCategorySheet(viewModel: viewModel, entryType: manageType)
            }
            .alert(
                L10n.Ledger.deleteCategory.localized,
                isPresented: $isConfirmingCategoryDelete
            ) {
                Button(L10n.Ledger.deleteCategory, role: .destructive) {
                    guard let category = categoryPendingDelete else {
                        LedgerCategoryDeleteLogger.step(
                            .failed,
                            categoryId: nil,
                            detail: "confirm_action_missing_pending_category source=manage_sheet"
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
            .alert(
                L10n.Common.notice.localized,
                isPresented: Binding(
                    get: {
                        viewModel.errorMessage?.isEmpty == false
                    },
                    set: { if $0 == false { viewModel.clearErrorMessage() } }
                )
            ) {
                Button(L10n.Common.ok, role: .cancel) {
                    viewModel.clearErrorMessage()
                }
            } message: {
                if let message = viewModel.errorMessage {
                    Text(message)
                }
            }
        }
    }

    private var categoriesSectionHeader: some View {
        HStack(spacing: 16) {
            Text(L10n.Ledger.manageCategories.localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if managedCategories.count >= 2 {
                Button {
                    withAnimation(.snappy) {
                        isSortingCategories.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isSortingCategories
                        ? AppLocalized.string(L10n.Common.completeSorting, locale: locale)
                        : AppLocalized.string(L10n.Ledger.sortCategories, locale: locale)
                )
            }
        }
        .textCase(nil)
    }

    private func attemptDelete(_ category: ExpenseCategory) {
        if viewModel.canDeleteCategory(category) {
            LedgerCategoryDeleteLogger.step(
                .confirmPresented,
                categoryId: category.id,
                categoryName: category.name,
                householdId: viewModel.currentHouseholdIdValue,
                detail: "source=manage_sheet"
            )
            categoryPendingDelete = category
            isConfirmingCategoryDelete = true
        } else {
            LedgerCategoryDeleteLogger.step(
                .blockedHasTransactions,
                categoryId: category.id,
                categoryName: category.name,
                householdId: viewModel.currentHouseholdIdValue,
                detail: "source=manage_sheet"
            )
            AnalyticsManager.log(event: .ledgerCategoryDeleteBlocked(reason: "has_linked_transactions"))
            deleteBlockedMessage = AppLocalized.string(
                L10n.Ledger.cannotDeleteCategoryWithEntries,
                locale: locale
            )
        }
    }
}
