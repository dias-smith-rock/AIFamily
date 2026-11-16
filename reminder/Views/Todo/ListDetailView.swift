import SwiftUI

/// 单个通用清单详情：勾选条目 + 底部快速新增。
struct ListDetailView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @ObservedObject var viewModel: ListViewModel
    let list: HouseholdList

    @State private var draftItemTitle = ""
    @State private var checkerNames: [UUID: String] = [:]
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        List {
            if viewModel.activeListId == list.id,
               viewModel.openItems.isEmpty,
               viewModel.checkedItems.isEmpty,
               viewModel.isLoading == false,
               viewModel.didFinishItemsLoad {
                ContentUnavailableView {
                    Label(L10n.Todo.listItemsEmpty.localized, systemImage: list.kind.systemImage)
                }
                .listRowBackground(Color.clear)
            }

            if viewModel.openItems.isEmpty == false {
                Section {
                    ForEach(viewModel.openItems) { item in
                        itemRow(item)
                    }
                    .onDelete { indexSet in
                        deleteOpenItems(at: indexSet)
                    }
                }
            }

            if viewModel.checkedItems.isEmpty == false {
                Section(L10n.Todo.listCheckedSection) {
                    ForEach(viewModel.checkedItems) { item in
                        itemRow(item)
                    }
                    .onDelete { indexSet in
                        deleteCheckedItems(at: indexSet)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background {
            SchedulePageBackgroundFill()
                .ignoresSafeArea()
        }
        .navigationTitle(Text(verbatim: list.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FamilyPrintToolbarButton { delivery in
                    printList(delivery: delivery)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addItemBar
        }
        .task(id: list.id) {
            await viewModel.loadItems(for: list.id)
        }
        .task(id: list.householdId) {
            checkerNames = await Self.checkerNames(in: list.householdId)
        }
        .refreshable {
            await LocalFirstSyncCoordinator.syncNow(reason: "pullToRefreshListDetail")
            await viewModel.loadItems(for: list.id)
        }
        .alert(
            L10n.Common.notice,
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
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
        .duoReadableContentWidth()
    }

    private func printList(delivery: FamilyPrintDelivery) {
        TodoPrintComposer.printPlannerItems(
            jobName: "\(GroupSwitcherData.currentName(for: appRouter)) · \(list.title)",
            title: list.title,
            open: viewModel.openItems.map(\.title),
            checked: viewModel.checkedItems.map(\.title),
            checkedHeading: L10n.Todo.listCheckedSection.string(locale: locale),
            locale: locale,
            delivery: delivery
        )
    }

    private func checkerCaption(for item: ListItem) -> String? {
        guard let membershipId = item.completedBy else { return nil }
        guard let name = checkerNames[membershipId], name.isEmpty == false else { return nil }
        return L10n.Todo.listCheckedBy.formatted(locale: locale, name)
    }

    private static func checkerNames(in householdId: UUID) async -> [UUID: String] {
        guard let snapshot = await HouseholdLocalCache.loadMembers(for: householdId) else { return [:] }
        var names: [UUID: String] = [:]
        for member in snapshot.members where member.householdId == householdId {
            let name: String?
            if let profile = member.profile {
                name = profile.displayName
            } else if let profileId = member.profileId,
                      let profile = snapshot.profiles.first(where: { $0.id == profileId }) {
                name = profile.displayName
            } else if let nickname = member.nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
                      nickname.isEmpty == false,
                      let profileId = member.profileId {
                name = GuestMemberDisplayName.resolvedDisplayName(stored: nickname, profileId: profileId)
            } else {
                name = member.nickname
            }
            if let name, name.isEmpty == false {
                names[member.id] = name
            }
        }
        return names
    }

    private func itemRow(_ item: ListItem) -> some View {
        Button {
            Task { await viewModel.toggleChecked(item) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                        .strikethrough(item.isChecked)
                    if item.isChecked, let caption = checkerCaption(for: item) {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var addItemBar: some View {
        HStack(spacing: 10) {
            TextField(
                AppLocalized.string(L10n.Todo.listAddItemPlaceholder, locale: locale),
                text: $draftItemTitle
            )
            .textFieldStyle(.roundedBorder)
            .focused($isDraftFocused)
            .onSubmit {
                Task { await submitDraft() }
            }

            Button {
                Task { await submitDraft() }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.ColorToken.accent)
            }
            .buttonStyle(.plain)
            .disabled(draftItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(L10n.Todo.listAddItemPlaceholder)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func submitDraft() async {
        let created = await viewModel.addItem(title: draftItemTitle, to: list)
        if created != nil {
            draftItemTitle = ""
            isDraftFocused = true
        }
    }

    private func deleteOpenItems(at offsets: IndexSet) {
        let targets = offsets.map { viewModel.openItems[$0] }
        Task {
            for item in targets {
                await viewModel.deleteItem(item)
            }
        }
    }

    private func deleteCheckedItems(at offsets: IndexSet) {
        let targets = offsets.map { viewModel.checkedItems[$0] }
        Task {
            for item in targets {
                await viewModel.deleteItem(item)
            }
        }
    }
}
