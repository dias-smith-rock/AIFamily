import SwiftUI

struct ScheduleSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel: ScheduleSearchViewModel

    var onOpenTask: (FamilyTask) -> Void
    var onOpenLedger: (LedgerTransaction) -> Void
    var onOpenMember: (FamilyProfile, UUID) -> Void

    init(
        viewModel: ScheduleSearchViewModel? = nil,
        onOpenTask: @escaping (FamilyTask) -> Void,
        onOpenLedger: @escaping (LedgerTransaction) -> Void,
        onOpenMember: @escaping (FamilyProfile, UUID) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AppViewModels.makeScheduleSearchViewModel())
        self.onOpenTask = onOpenTask
        self.onOpenLedger = onOpenLedger
        self.onOpenMember = onOpenMember
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                if hasNoResults {
                    Text(L10n.Schedule.searchNoResults.localized)
                        .foregroundStyle(.secondary)
                }

                resultSection(
                    title: L10n.Schedule.searchSectionTasks,
                    items: viewModel.taskResults
                ) { item in
                    if let task = item.task { onOpenTask(task) }
                }
                resultSection(
                    title: L10n.Schedule.searchSectionTodos,
                    items: viewModel.todoResults
                ) { item in
                    if let task = item.task { onOpenTask(task) }
                }
                resultSection(
                    title: L10n.Schedule.searchSectionLedger,
                    items: viewModel.ledgerResults
                ) { item in
                    if let tx = item.transaction { onOpenLedger(tx) }
                }
                resultSection(
                    title: L10n.Schedule.searchSectionMembers,
                    items: viewModel.memberResults
                ) { item in
                    if let profile = item.profile {
                        onOpenMember(profile, item.householdId)
                    }
                }
            }
            .navigationTitle(L10n.Schedule.search.localized)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: AppLocalized.string(L10n.Schedule.searchPlaceholder, locale: locale)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close) { dismiss() }
                }
            }
            .onChange(of: viewModel.query) { _, _ in
                triggerSearch()
            }
            .onAppear {
                triggerSearch()
            }
        }
    }

    private var hasNoResults: Bool {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && viewModel.isSearching == false
            && viewModel.taskResults.isEmpty
            && viewModel.todoResults.isEmpty
            && viewModel.ledgerResults.isEmpty
            && viewModel.memberResults.isEmpty
    }

    @ViewBuilder
    private func resultSection(
        title: L10n.Entry,
        items: [ScheduleSearchViewModel.ResultItem],
        onTap: @escaping (ScheduleSearchViewModel.ResultItem) -> Void
    ) -> some View {
        if items.isEmpty == false {
            Section(title) {
                ForEach(items) { item in
                    Button {
                        dismiss()
                        onTap(item)
                    } label: {
                        HStack(spacing: 10) {
                            HouseholdColorDot(householdId: item.householdId, size: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                Text(item.householdName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func triggerSearch() {
        let names = Dictionary(
            uniqueKeysWithValues: appRouter.selectableHouseholds.map { ($0.id, $0.name) }
        )
        viewModel.scheduleSearch(
            householdIds: appRouter.selectedHouseholdIds,
            householdNames: names
        )
    }
}
