import SwiftUI

struct EditCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: FamilyLedgerViewModel

    let category: ExpenseCategory

    @State private var nameText: String
    @State private var iconText: String
    @State private var newTagName = ""
    @State private var isSaving = false
    @State private var tagPendingDelete: CategoryTag?

    init(viewModel: FamilyLedgerViewModel, category: ExpenseCategory) {
        self.viewModel = viewModel
        self.category = category
        _nameText = State(initialValue: category.localizedName(locale: AppSettingsManager.shared.appLocale))
        _iconText = State(initialValue: LedgerCategoryIconPresets.resolvedSelection(from: category.icon))
    }

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
                    let tags = viewModel.tags(for: category.id)
                    if tags.isEmpty == false {
                        LedgerTagCapsuleFlow(spacing: 8) {
                            ForEach(tags) { tag in
                                editableTagCapsule(tag)
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
                            Task { await addTag() }
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text(L10n.Ledger.tags.localized)
                }
            }
            .navigationTitle(L10n.Ledger.editCategory.localized)
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

    private var canSave: Bool {
        nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    @ViewBuilder
    private func editableTagCapsule(_ tag: CategoryTag) -> some View {
        HStack(spacing: 4) {
            Text(tag.localizedName(locale: locale))
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if tag.isPreset == false {
                Button {
                    tagPendingDelete = tag
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Ledger.deleteTag.localized)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill))
        .clipShape(Capsule())
    }

    private func save() async {
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = iconText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }

        isSaving = true
        defer { isSaving = false }

        let nameToPersist: String
        if category.presetKey != nil {
            let localized = category.localizedName(locale: locale)
            nameToPersist = (name == localized) ? category.name : name
        } else {
            nameToPersist = name
        }

        do {
            try await viewModel.updateCategory(
                category,
                name: nameToPersist,
                icon: icon.isEmpty ? "🏷️" : icon,
                colorHex: category.colorHex
            )
            dismiss()
        } catch {
            // errorMessage surfaced via ledger reload if needed
        }
    }

    private func addTag() async {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }
        try? await viewModel.addTag(categoryId: category.id, name: name)
        newTagName = ""
    }
}

/// 横向流式排布：放不下则换行，子视图保持固有宽度（胶囊不拉伸）。
struct LedgerTagCapsuleFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        // 宽度未知时不能按 infinity 测算，否则不换行、高度偏小，背景会盖住相邻内容。
        guard let proposedWidth = proposal.width, proposedWidth.isFinite, proposedWidth > 0 else {
            var totalWidth: CGFloat = 0
            var height: CGFloat = 0
            for (index, size) in sizes.enumerated() {
                if index > 0 { totalWidth += spacing }
                totalWidth += size.width
                height = max(height, size.height)
            }
            return CGSize(width: totalWidth, height: height)
        }

        return flowSize(sizes: sizes, maxWidth: proposedWidth)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX

        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            if x > bounds.minX, x + spacing + size.width > maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            if x > bounds.minX { x += spacing }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func flowSize(sizes: [CGSize], maxWidth: CGFloat) -> CGSize {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for size in sizes {
            if x > 0, x + spacing + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            if x > 0 { x += spacing }
            x += size.width
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x)
            totalHeight = max(totalHeight, y + rowHeight)
        }

        return CGSize(width: maxWidth, height: totalHeight)
    }
}
