import SwiftUI

/// To-Dos Tab「清单」分区：家庭共享通用清单列表。
struct ListsHomeView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: ListViewModel
    @Binding var selectedList: HouseholdList?

    @State private var isShowingCreateSheet = false
    @State private var listPendingDelete: HouseholdList?
    @State private var listPendingRename: HouseholdList?
    @State private var renameDraft = ""

    var body: some View {
        Group {
            if viewModel.isLoading, viewModel.lists.isEmpty {
                ProgressView(L10n.Common.loading.localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.lists.isEmpty {
                ContentUnavailableView {
                    Label(L10n.Todo.listsEmpty.localized, systemImage: "list.bullet.rectangle")
                } description: {
                    Text(L10n.Todo.listsEmptyHint.localized)
                } actions: {
                    Button(L10n.Todo.newList) {
                        isShowingCreateSheet = true
                    }
                }
            } else {
                listScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .duoReadableContentWidth()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    isShowingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(AppTheme.ColorToken.accent, in: Circle())
                        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Todo.newList)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateHouseholdListSheet { title, kind, start, end in
                if let created = await viewModel.createList(
                    title: title,
                    kind: kind,
                    tripStart: start,
                    tripEnd: end
                ) {
                    selectedList = created
                }
            }
        }
        .sheet(item: $listPendingRename) { list in
            RenameHouseholdListSheet(initialTitle: list.title) { title in
                await viewModel.renameList(list, title: title)
            }
        }
        .alert(
            L10n.Todo.listDeleteConfirmTitle,
            isPresented: Binding(
                get: { listPendingDelete != nil },
                set: { if $0 == false { listPendingDelete = nil } }
            )
        ) {
            Button(L10n.Common.cancel, role: .cancel) {
                listPendingDelete = nil
            }
            Button(L10n.Common.delete, role: .destructive) {
                if let list = listPendingDelete {
                    Task { await viewModel.deleteList(list) }
                }
                listPendingDelete = nil
            }
        } message: {
            Text(L10n.Todo.listDeleteConfirmMessage.localized)
        }
    }

    private var listScroll: some View {
        List {
            ForEach(viewModel.lists) { list in
                Button {
                    selectedList = list
                } label: {
                    HouseholdListRow(list: list)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        listPendingDelete = list
                    } label: {
                        Label(L10n.Common.delete.localized, systemImage: "trash")
                    }
                    Button {
                        listPendingRename = list
                        renameDraft = list.title
                    } label: {
                        Label(L10n.Todo.listRename.localized, systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await LocalFirstSyncCoordinator.syncNow(reason: "pullToRefreshPlanner")
            await viewModel.loadLists(force: true)
        }
    }
}

private struct HouseholdListRow: View {
    let list: HouseholdList

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: list.kind.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.ColorToken.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(list.kindTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

extension ListKind {
    var kindTitle: LocalizedStringResource {
        switch self {
        case .shopping: L10n.Todo.listKindShopping.localized
        case .trip: L10n.Todo.listKindTrip.localized
        case .custom: L10n.Todo.listKindCustom.localized
        }
    }
}

extension HouseholdList {
    var kindTitle: LocalizedStringResource {
        kind.kindTitle
    }
}

// MARK: - Create / Rename sheets

private struct CreateHouseholdListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let onCreate: (String, ListKind, Date?, Date?) async -> Void

    @State private var title = ""
    @State private var kind: ListKind = .shopping
    @State private var tripStart = Date()
    @State private var tripEnd = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.Todo.listName) {
                    TextField(
                        AppLocalized.string(L10n.Todo.listNamePlaceholder, locale: locale),
                        text: $title
                    )
                }
                Section(L10n.Todo.listKind) {
                    Picker(L10n.Todo.listKind.localized, selection: $kind) {
                        ForEach(ListKind.allCases) { option in
                            Label {
                                Text(option.kindTitle)
                            } icon: {
                                Image(systemName: option.systemImage)
                            }
                            .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if kind == .trip {
                    Section {
                        DatePicker(
                            L10n.Todo.listTripStart.localized,
                            selection: $tripStart,
                            displayedComponents: .date
                        )
                        DatePicker(
                            L10n.Todo.listTripEnd.localized,
                            selection: $tripEnd,
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle(L10n.Todo.newList.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Todo.listCreate) {
                        Task {
                            isSaving = true
                            await onCreate(
                                title,
                                kind,
                                kind == .trip ? tripStart : nil,
                                kind == .trip ? tripEnd : nil
                            )
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .duoReadableContentWidth()
    }
}

private struct RenameHouseholdListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let initialTitle: String
    let onRename: (String) async -> Void

    @State private var title: String
    @State private var isSaving = false

    init(initialTitle: String, onRename: @escaping (String) async -> Void) {
        self.initialTitle = initialTitle
        self.onRename = onRename
        _title = State(initialValue: initialTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.Todo.listName) {
                    TextField(
                        AppLocalized.string(L10n.Todo.listNamePlaceholder, locale: locale),
                        text: $title
                    )
                }
            }
            .navigationTitle(L10n.Todo.listRename.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        Task {
                            isSaving = true
                            await onRename(title)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .duoReadableContentWidth()
    }
}
