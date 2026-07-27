import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

struct ScheduleSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @StateObject private var viewModel: ScheduleSearchViewModel
    @StateObject private var scheduleViewModel = AppViewModels.makeScheduleViewModel()

    @State private var taskForDetail: FamilyTask?
    @State private var currentMembershipRole: MembershipRole = .member

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
                    openTaskResult(item)
                }
                resultSection(
                    title: L10n.Schedule.searchSectionTodos,
                    items: viewModel.todoResults
                ) { item in
                    openTaskResult(item)
                }
                resultSection(
                    title: L10n.Schedule.searchSectionLedger,
                    items: viewModel.ledgerResults
                ) { item in
                    if let tx = item.transaction {
                        dismiss()
                        onOpenLedger(tx)
                    }
                }
                resultSection(
                    title: L10n.Schedule.searchSectionMembers,
                    items: viewModel.memberResults
                ) { item in
                    if let profile = item.profile {
                        dismiss()
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
            .sheet(item: $taskForDetail) { task in
                NavigationStack {
                    TaskDetailView(
                        initialTask: task,
                        currentUserRole: currentMembershipRole,
                        assigneeDisplayName: scheduleViewModel.assigneeLabel(for: task, locale: locale),
                        scheduleViewModel: scheduleViewModel
                    )
                    .environmentObject(appRouter)
                }
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openTaskResult(_ item: ScheduleSearchViewModel.ResultItem) {
        guard let task = item.task else { return }
        scheduleViewModel.setHouseholdContext(item.householdId)
        scheduleViewModel.setViewHouseholdIds(appRouter.selectedHouseholdIds)
        Task { @MainActor in
            await refreshMembershipRole(for: item.householdId)
            taskForDetail = task
            onOpenTask(task)
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

    private func refreshMembershipRole(for householdId: UUID) async {
        guard let membershipId = appRouter.selectableHouseholds
            .first(where: { $0.id == householdId })?
            .membershipId
            ?? appRouter.selectedMembershipId
        else {
            currentMembershipRole = .member
            return
        }
        #if canImport(Supabase)
        struct MembershipRoleRow: Decodable {
            let role: MembershipRole
        }
        do {
            let rows: [MembershipRoleRow] = try await SupabaseManager.shared.client
                .from("household_memberships")
                .select("role")
                .eq("id", value: membershipId.uuidString)
                .limit(1)
                .execute()
                .value
            currentMembershipRole = rows.first?.role ?? .member
        } catch {
            currentMembershipRole = .member
        }
        #else
        currentMembershipRole = .member
        #endif
    }
}
