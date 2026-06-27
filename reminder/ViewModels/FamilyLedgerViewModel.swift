import Foundation
import Combine

@MainActor
final class FamilyLedgerViewModel: ObservableObject {
    enum Segment: String, CaseIterable, Identifiable {
        case expense
        case points

        var id: String { rawValue }
    }

    @Published private(set) var expenseEntries: [FamilyTask] = []
    @Published private(set) var pointsEntries: [PointsLedgerEntry] = []
    @Published private(set) var categories: [ExpenseCategory] = []
    @Published private(set) var householdMembers: [HouseholdMembership] = []
    @Published private(set) var familyProfiles: [FamilyProfile] = []
    @Published private(set) var selectedPointsProfileId: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let taskService: TaskDataService
    private let ledgerService: LedgerDataService
    private let membershipService: HouseholdMembershipDataService
    private let familyProfileService: FamilyProfileDataService

    private var currentHouseholdId: UUID?
    private var loadedHouseholdId: UUID?
    private var reloadCancellable: AnyCancellable?

    init(
        taskService: TaskDataService,
        ledgerService: LedgerDataService,
        membershipService: HouseholdMembershipDataService,
        familyProfileService: FamilyProfileDataService
    ) {
        self.taskService = taskService
        self.ledgerService = ledgerService
        self.membershipService = membershipService
        self.familyProfileService = familyProfileService

        reloadCancellable = NotificationCenter.default
            .publisher(for: .ledgerDataDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadInitialData(force: true)
                }
            }
    }

    func setHouseholdContext(_ householdId: UUID?) {
        let changed = currentHouseholdId != householdId
        currentHouseholdId = householdId
        if householdId == nil {
            expenseEntries = []
            pointsEntries = []
            categories = []
            householdMembers = []
            familyProfiles = []
            selectedPointsProfileId = nil
            loadedHouseholdId = nil
        } else if changed {
            loadedHouseholdId = nil
            selectedPointsProfileId = nil
        }
    }

    func loadInitialDataIfNeeded() async {
        guard let householdId = currentHouseholdId else {
            errorMessage = AppLocalized.localized(L10n.Family.noGroupIsCurrentlySelected)
            return
        }
        if loadedHouseholdId == householdId { return }
        await loadInitialData(force: false)
    }

    func loadInitialData(force: Bool) async {
        guard let householdId = currentHouseholdId else { return }
        if force == false, loadedHouseholdId == householdId { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let rosterTask = membershipService.fetchMemberRoster(in: householdId, activeOnly: true)
            async let tasksTask = taskService.fetchTasks(in: householdId)
            async let categoriesTask = ledgerService.ensureDefaultCategories(in: householdId)

            let roster = try await rosterTask
            let allTasks = try await tasksTask
            categories = try await categoriesTask

            householdMembers = roster.memberships
            familyProfiles = roster.profiles

            expenseEntries = allTasks
                .filter(\.isLedgerEntry)
                .sorted { ($0.dueDate ?? $0.createdAt) > ($1.dueDate ?? $1.createdAt) }

            resolveSelectedPointsProfile(
                membershipId: nil,
                canManageHousehold: true
            )

            await reloadPointsLedger()
            loadedHouseholdId = householdId
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func configurePointsContext(
        membershipId: UUID?,
        canManageHousehold: Bool
    ) {
        resolveSelectedPointsProfile(
            membershipId: membershipId,
            canManageHousehold: canManageHousehold
        )
        Task { await reloadPointsLedger() }
    }

    func selectPointsProfile(_ profileId: UUID) {
        selectedPointsProfileId = profileId
        Task { await reloadPointsLedger() }
    }

    func pointsBalance(for profileId: UUID) -> Int {
        pointsEntries
            .filter { $0.targetProfileId == profileId }
            .reduce(0) { $0 + $1.amount }
    }

    var selectableChildProfiles: [FamilyProfile] {
        familyProfiles.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    var monthExpenseTotal: Double {
        expenseEntries
            .filter { isInCurrentMonth($0.dueDate ?? $0.createdAt) }
            .filter(\.isLedgerExpenseEntry)
            .reduce(0) { $0 + ($1.actualAmount ?? 0) }
    }

    var monthIncomeTotal: Double {
        expenseEntries
            .filter { isInCurrentMonth($0.dueDate ?? $0.createdAt) }
            .filter(\.isLedgerIncomeEntry)
            .reduce(0) { $0 + ($1.actualAmount ?? 0) }
    }

    var monthNetTotal: Double {
        monthIncomeTotal - monthExpenseTotal
    }

    func membershipDisplayName(for membershipId: UUID?) -> String {
        guard let membershipId else { return "—" }
        return MemberDisplayName.displayName(
            forMembershipId: membershipId,
            members: householdMembers,
            profiles: familyProfiles
        ) ?? "—"
    }

    func createExpenseEntry(
        isIncome: Bool,
        amount: Double,
        title: String,
        note: String?,
        categoryLabel: String,
        payerMembershipId: UUID,
        creatorMembershipId: UUID
    ) async throws {
        guard let householdId = currentHouseholdId else { return }
        guard amount > 0 else { return }

        let now = Date()
        let task = FamilyTask(
            id: UUID(),
            householdId: householdId,
            creatorId: creatorMembershipId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? categoryLabel
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            status: .completed,
            priority: .normal,
            taskType: isIncome ? FamilyTask.ledgerIncomeTaskType : FamilyTask.ledgerExpenseTaskType,
            dueDate: now,
            isAllDay: true,
            actualAmount: amount,
            payerId: payerMembershipId,
            expenseCategory: categoryLabel,
            createdAt: now,
            updatedAt: now
        )

        let created = try await ledgerService.createLedgerTask(task)
        expenseEntries.insert(created, at: 0)
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
    }

    func createPointsEntry(
        isRedemption: Bool,
        points: Int,
        description: String,
        targetProfileId: UUID
    ) async throws {
        guard let householdId = currentHouseholdId else { return }
        guard points > 0 else { return }

        let signedAmount = isRedemption ? -points : points
        if isRedemption {
            let balance = try await fetchPointsBalance(for: targetProfileId)
            guard balance + signedAmount >= 0 else {
                throw LedgerValidationError.insufficientPoints
            }
        }

        let entry = PointsLedgerEntry(
            id: UUID(),
            householdId: householdId,
            targetProfileId: targetProfileId,
            amount: signedAmount,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (isRedemption ? AppLocalized.localized(L10n.Ledger.defaultRedemptionNote) : AppLocalized.localized(L10n.Ledger.defaultEarnNote))
                : description.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date()
        )

        let created = try await ledgerService.insertPointsLedgerEntry(entry)
        if selectedPointsProfileId == targetProfileId || selectedPointsProfileId == nil {
            pointsEntries.insert(created, at: 0)
        } else {
            await reloadPointsLedger()
        }
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
    }

    private func reloadPointsLedger() async {
        guard let householdId = currentHouseholdId else { return }
        do {
            pointsEntries = try await ledgerService.fetchPointsLedger(
                in: householdId,
                targetProfileId: selectedPointsProfileId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveSelectedPointsProfile(
        membershipId: UUID?,
        canManageHousehold: Bool
    ) {
        if canManageHousehold {
            if selectedPointsProfileId == nil {
                selectedPointsProfileId = selectableChildProfiles.first?.id
            }
            return
        }

        if let membershipId,
           let membership = householdMembers.first(where: { $0.id == membershipId }),
           let profileId = membership.profileId {
            selectedPointsProfileId = profileId
            return
        }

        selectedPointsProfileId = selectableChildProfiles.first?.id
    }

    private func isInCurrentMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
    }

    private func fetchPointsBalance(for profileId: UUID) async throws -> Int {
        guard let householdId = currentHouseholdId else { return 0 }
        let entries = try await ledgerService.fetchPointsLedger(
            in: householdId,
            targetProfileId: profileId
        )
        return entries.reduce(0) { $0 + $1.amount }
    }
}

enum LedgerValidationError: LocalizedError {
    case insufficientPoints

    var errorDescription: String? {
        switch self {
        case .insufficientPoints:
            String(localized: String.LocalizationValue(L10n.Ledger.insufficientPointsMessage.key), table: L10n.Table.ledger.rawValue)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
