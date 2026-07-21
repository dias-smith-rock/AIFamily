import SwiftUI

struct ManageCategoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: FamilyLedgerViewModel

    @State private var manageType: LedgerEntryType = .expense
    @State private var newCategoryName = ""
    @State private var newCategoryIcon = "🏷️"
    @State private var newTagName = ""
    @State private var selectedCategoryForTag: UUID?
    @State private var categoryPendingDelete: ExpenseCategory?
    @State private var tagPendingDelete: CategoryTag?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $manageType) {
                        Text(L10n.Ledger.expense.localized).tag(LedgerEntryType.expense)
                        Text(L10n.Ledger.income.localized).tag(LedgerEntryType.income)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(viewModel.categories(for: manageType)) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(category.displayLabel)
                                    .font(.body.weight(.semibold))
                                Spacer()
                                if category.isPreset == false {
                                    Button(role: .destructive) {
                                        categoryPendingDelete = category
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }

                            ForEach(viewModel.tags(for: category.id)) { tag in
                                HStack {
                                    Text(tag.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if tag.isPreset == false {
                                        Button(role: .destructive) {
                                            tagPendingDelete = tag
                                        } label: {
                                            Image(systemName: "minus.circle")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(L10n.Ledger.addCategory.localized) {
                    TextField(AppLocalized.string(L10n.Ledger.categoryName, locale: locale), text: $newCategoryName)
                    TextField(AppLocalized.string(L10n.Ledger.iconEmoji, locale: locale), text: $newCategoryIcon)
                    Button(L10n.Ledger.addCategory.localized) {
                        Task { await addCategory() }
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section(L10n.Ledger.addTag.localized) {
                    Picker(L10n.Ledger.category.localized, selection: tagCategoryBinding) {
                        ForEach(viewModel.categories(for: manageType)) { category in
                            Text(category.displayLabel).tag(category.id)
                        }
                    }
                    TextField(AppLocalized.string(L10n.Ledger.tagName, locale: locale), text: $newTagName)
                    Button(L10n.Ledger.addTag.localized) {
                        Task { await addTag() }
                    }
                    .disabled(
                        newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || selectedCategoryForTag == nil
                    )
                }
            }
            .navigationTitle(L10n.Ledger.manageCategories.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                }
            }
            .onAppear {
                selectedCategoryForTag = viewModel.categories(for: manageType).first?.id
            }
            .onChange(of: manageType) { _, _ in
                selectedCategoryForTag = viewModel.categories(for: manageType).first?.id
            }
            .alert(
                L10n.Ledger.deleteCategory.localized,
                isPresented: Binding(
                    get: { categoryPendingDelete != nil },
                    set: { if $0 == false { categoryPendingDelete = nil } }
                )
            ) {
                Button(L10n.Ledger.deleteCategory, role: .destructive) {
                    Task {
                        if let category = categoryPendingDelete {
                            try? await viewModel.softDeleteCategory(category)
                        }
                        categoryPendingDelete = nil
                    }
                }
                Button(L10n.Common.cancel, role: .cancel) {
                    categoryPendingDelete = nil
                }
            }
            .alert(
                L10n.Ledger.deleteTag.localized,
                isPresented: Binding(
                    get: { tagPendingDelete != nil },
                    set: { if $0 == false { tagPendingDelete = nil } }
                )
            ) {
                Button(L10n.Ledger.deleteTag, role: .destructive) {
                    Task {
                        if let tag = tagPendingDelete {
                            try? await viewModel.softDeleteTag(tag)
                        }
                        tagPendingDelete = nil
                    }
                }
                Button(L10n.Common.cancel, role: .cancel) {
                    tagPendingDelete = nil
                }
            }
        }
    }

    private var tagCategoryBinding: Binding<UUID> {
        Binding(
            get: { selectedCategoryForTag ?? viewModel.categories(for: manageType).first?.id ?? UUID() },
            set: { selectedCategoryForTag = $0 }
        )
    }

    private func addCategory() async {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = newCategoryIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }
        try? await viewModel.addCategory(
            type: manageType,
            name: name,
            icon: icon.isEmpty ? "🏷️" : icon
        )
        newCategoryName = ""
        newCategoryIcon = "🏷️"
    }

    private func addTag() async {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false,
              let categoryId = selectedCategoryForTag else { return }
        try? await viewModel.addTag(categoryId: categoryId, name: name)
        newTagName = ""
    }
}
