import Foundation
import Combine

@MainActor
final class FamilyLedgerViewModel: ObservableObject {
    @Published private(set) var transactions: [LedgerTransaction] = []
    @Published private(set) var categories: [ExpenseCategory] = []
    @Published private(set) var tags: [CategoryTag] = []
    @Published private(set) var householdMembers: [HouseholdMembership] = []
    @Published private(set) var familyProfiles: [FamilyProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    @Published var reportPeriod: LedgerReportPeriod = .month
    @Published var reportPayerFilterId: UUID?
    @Published var reportTargetFilterId: UUID?

    /// 首页周期粒度与翻页锚点（与报表共用 `LedgerReportPeriod`）。
    @Published var ledgerGranularity: LedgerReportPeriod = .month
    @Published var periodAnchor: Date = Date()

    private let ledgerService: LedgerDataService
    private let membershipService: HouseholdMembershipDataService
    private let familyProfileService: FamilyProfileDataService

    private var currentHouseholdId: UUID?
    private var loadedHouseholdId: UUID?
    private var reloadCancellable: AnyCancellable?

    init(
        ledgerService: LedgerDataService,
        membershipService: HouseholdMembershipDataService,
        familyProfileService: FamilyProfileDataService
    ) {
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

    var currentHouseholdIdValue: UUID? { currentHouseholdId }

    func setHouseholdContext(_ householdId: UUID?) {
        let changed = currentHouseholdId != householdId
        currentHouseholdId = householdId
        if householdId == nil {
            transactions = []
            categories = []
            tags = []
            householdMembers = []
            familyProfiles = []
            loadedHouseholdId = nil
        } else if changed {
            loadedHouseholdId = nil
        }
    }

    func loadInitialDataIfNeeded() async {
        guard let householdId = currentHouseholdId else {
            errorMessage = AppLocalized.localized(L10n.Family.noGroupIsCurrentlySelected)
            return
        }
        if loadedHouseholdId == householdId { return }
        await loadRoster()
        await loadLedgerData(force: false)
    }

    func loadRoster() async {
        guard let householdId = currentHouseholdId else { return }
        do {
            let roster = try await membershipService.fetchMemberRoster(in: householdId, activeOnly: true)
            householdMembers = roster.memberships
            familyProfiles = roster.profiles
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadLedgerData(force: Bool) async {
        guard let householdId = currentHouseholdId else { return }
        if force == false, loadedHouseholdId == householdId { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // 幂等补种；失败不阻断后续读取（例如旧家庭已有分类）
        do {
            try await ledgerService.ensurePresetCategories(in: householdId)
        } catch {
            errorMessage = error.localizedDescription
        }

        do {
            async let categoriesTask = ledgerService.fetchCategories(
                in: householdId,
                type: nil,
                includeDeleted: false
            )
            async let tagsTask = ledgerService.fetchTags(
                in: householdId,
                categoryId: nil,
                includeDeleted: false
            )
            async let txTask = ledgerService.fetchTransactions(in: householdId)

            categories = try await categoriesTask
            tags = try await tagsTask
            var rows = try await txTask

            let mappings = try await ledgerService.fetchTagMappings(for: rows.map(\.id))
            let tagsByTx = Dictionary(grouping: mappings, by: \.transactionId)
            for index in rows.indices {
                rows[index].tagSnapshots = (tagsByTx[rows[index].id] ?? []).map(\.tagNameSnapshot)
            }
            transactions = rows
            loadedHouseholdId = householdId
            if categories.isEmpty == false {
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadInitialData(force: Bool) async {
        await loadRoster()
        await loadLedgerData(force: force)
    }

    func categories(for type: LedgerEntryType) -> [ExpenseCategory] {
        categories.filter { $0.type == type && $0.isDeleted == false }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func tags(for categoryId: UUID) -> [CategoryTag] {
        tags.filter { $0.categoryId == categoryId && $0.isDeleted == false }
    }

    func profileDisplayName(for profileId: UUID?) -> String {
        guard let profileId,
              let profile = familyProfiles.first(where: { $0.id == profileId }) else {
            return "—"
        }
        return profile.displayName
    }

    // MARK: - Summary / Report

    var filteredTransactionsForReport: [LedgerTransaction] {
        transactions.filter { tx in
            guard isInSelectedPeriod(tx.transactionTime) else { return false }
            if let payerId = reportPayerFilterId, tx.payerId != payerId {
                return false
            }
            if let targetId = reportTargetFilterId,
               tx.targetMemberIds.contains(targetId) == false {
                return false
            }
            return true
        }
    }

    var reportExpenseTotal: Double {
        filteredTransactionsForReport
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }

    var reportIncomeTotal: Double {
        filteredTransactionsForReport
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
    }

    var reportNetTotal: Double {
        reportIncomeTotal - reportExpenseTotal
    }

    var categoryExpenseBreakdown: [(name: String, icon: String?, amount: Double)] {
        let expenses = filteredTransactionsForReport.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses, by: \.categoryNameSnapshot)
        return grouped
            .map { name, rows in
                (
                    name: name,
                    icon: rows.first?.categoryIconSnapshot,
                    amount: rows.reduce(0) { $0 + $1.amount }
                )
            }
            .sorted { $0.amount > $1.amount }
    }

    var monthExpenseTotal: Double {
        periodTotals(for: .month, anchor: Date()).expense
    }

    var monthIncomeTotal: Double {
        periodTotals(for: .month, anchor: Date()).income
    }

    var monthNetTotal: Double {
        monthIncomeTotal - monthExpenseTotal
    }

    // MARK: - Home period navigation

    var expenseTotalInPeriod: Double {
        dashboardTransactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }

    var incomeTotalInPeriod: Double {
        dashboardTransactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
    }

    var dashboardTransactions: [LedgerTransaction] {
        transactions.filter {
            isInPeriod($0.transactionTime, period: ledgerGranularity, anchor: periodAnchor)
        }
    }

    func amount(for categoryId: UUID, type: LedgerEntryType) -> Double {
        dashboardTransactions
            .filter { $0.type == type && $0.categoryId == categoryId }
            .reduce(0) { $0 + $1.amount }
    }

    func shiftPeriod(by delta: Int) {
        let calendar = Calendar.current
        let component = ledgerGranularity.calendarComponent
        if let next = calendar.date(byAdding: component, value: delta, to: periodAnchor) {
            periodAnchor = next
        }
    }

    func periodTitle(locale: Locale) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = locale
        switch ledgerGranularity {
        case .day:
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: periodAnchor)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: periodAnchor) else {
                return ""
            }
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            let start = formatter.string(from: interval.start)
            let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let end = formatter.string(from: endDate)
            return "\(start) – \(end)"
        case .month:
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            return formatter.string(from: periodAnchor)
        case .year:
            formatter.setLocalizedDateFormatFromTemplate("yyyy")
            return formatter.string(from: periodAnchor)
        }
    }

    // MARK: - Mutations

    func createTransaction(_ draft: LedgerTransactionDraft) async throws {
        let created = try await ledgerService.createTransaction(draft)
        transactions.insert(created, at: 0)
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
    }

    func softDeleteCategory(_ category: ExpenseCategory) async throws {
        try await ledgerService.softDeleteCategory(id: category.id)
        categories.removeAll { $0.id == category.id }
        tags.removeAll { $0.categoryId == category.id }
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
    }

    func softDeleteTag(_ tag: CategoryTag) async throws {
        try await ledgerService.softDeleteTag(id: tag.id)
        tags.removeAll { $0.id == tag.id }
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
    }

    func addCategory(type: LedgerEntryType, name: String, icon: String) async throws {
        guard let householdId = currentHouseholdId else { return }
        let created = try await ledgerService.createCategory(
            householdId: householdId,
            type: type,
            name: name,
            icon: icon,
            colorHex: "#007AFF"
        )
        categories.append(created)
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
    }

    func addTag(categoryId: UUID, name: String) async throws {
        guard let householdId = currentHouseholdId else { return }
        let created = try await ledgerService.createTag(
            householdId: householdId,
            categoryId: categoryId,
            name: name
        )
        tags.append(created)
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
    }

    // MARK: - Private

    private func periodTotals(
        for period: LedgerReportPeriod,
        anchor: Date
    ) -> (expense: Double, income: Double) {
        let rows = transactions.filter { isInPeriod($0.transactionTime, period: period, anchor: anchor) }
        let expense = rows.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let income = rows.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        return (expense, income)
    }

    private func isInSelectedPeriod(_ date: Date) -> Bool {
        isInPeriod(date, period: reportPeriod, anchor: Date())
    }

    private func isInPeriod(_ date: Date, period: LedgerReportPeriod, anchor: Date) -> Bool {
        let calendar = Calendar.current
        switch period {
        case .day:
            return calendar.isDate(date, equalTo: anchor, toGranularity: .day)
        case .week:
            return calendar.isDate(date, equalTo: anchor, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(date, equalTo: anchor, toGranularity: .month)
        case .year:
            return calendar.isDate(date, equalTo: anchor, toGranularity: .year)
        }
    }
}
