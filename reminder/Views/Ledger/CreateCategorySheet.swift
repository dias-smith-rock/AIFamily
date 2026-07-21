import SwiftUI

struct CreateCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: FamilyLedgerViewModel

    let entryType: LedgerEntryType

    @State private var nameText = ""
    @State private var iconText = "🏷️"
    @State private var draftTagNames: [String] = []
    @State private var newTagName = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        AppLocalized.string(L10n.Ledger.categoryName, locale: locale),
                        text: $nameText
                    )
                }

                Section {
                    LedgerCategoryIconPicker(selectedIcon: $iconText)
                } header: {
                    Text(L10n.Ledger.iconEmoji.localized)
                }

                Section {
                    if draftTagNames.isEmpty == false {
                        LedgerTagCapsuleFlow(spacing: 8) {
                            ForEach(draftTagNames, id: \.self) { tagName in
                                draftTagCapsule(tagName)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }

                    HStack {
                        TextField(
                            AppLocalized.string(L10n.Ledger.tagName, locale: locale),
                            text: $newTagName
                        )
                        Button(L10n.Ledger.addTag.localized) {
                            addDraftTag()
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text(L10n.Ledger.tags.localized)
                }
            }
            .navigationTitle(L10n.Ledger.addCategory.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.save) {
                        Task { await save() }
                    }
                    .disabled(canSave == false || isSaving)
                }
            }
        }
    }

    private var canSave: Bool {
        nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    @ViewBuilder
    private func draftTagCapsule(_ tagName: String) -> some View {
        HStack(spacing: 4) {
            Text(tagName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Button {
                draftTagNames.removeAll { $0 == tagName }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Ledger.deleteTag.localized)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill))
        .clipShape(Capsule())
    }

    private func addDraftTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }
        guard draftTagNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) == false else {
            newTagName = ""
            return
        }
        draftTagNames.append(name)
        newTagName = ""
    }

    private func save() async {
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = iconText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            guard let created = try await viewModel.addCategory(
                type: entryType,
                name: name,
                icon: icon.isEmpty ? "🏷️" : icon
            ) else { return }

            for tagName in draftTagNames {
                try await viewModel.addTag(categoryId: created.id, name: tagName)
            }
            dismiss()
        } catch {
            // surfaced via ledger error if needed
        }
    }
}
