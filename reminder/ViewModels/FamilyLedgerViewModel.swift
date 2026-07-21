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
                    let token = LedgerWalletLoadLogger.nextToken()
                    LedgerWalletLoadLogger.step(
                        .notificationReload,
                        token: token,
                        source: "ledgerDataDidChange",
                        householdId: self?.currentHouseholdId
                    )
                    await self?.loadInitialData(force: true, loadToken: token, source: "notification")
                }
            }
    }

    var currentHouseholdIdValue: UUID? { currentHouseholdId }

    func clearErrorMessage() {
        errorMessage = nil
    }

    func setHouseholdContext(_ householdId: UUID?) {
        let changed = currentHouseholdId != householdId
        LedgerWalletLoadLogger.step(
            .setHousehold,
            source: "setHouseholdContext",
            householdId: householdId,
            detail: "changed=\(changed) prev=\(currentHouseholdId?.uuidString.lowercased() ?? "nil")"
        )
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

    func loadRoster(loadToken: Int? = nil, source: String = "unspecified") async {
        guard let householdId = currentHouseholdId else { return }
        let token = loadToken ?? LedgerWalletLoadLogger.nextToken()
        LedgerWalletLoadLogger.step(
            .rosterStart,
            token: token,
            source: source,
            householdId: householdId
        )
        do {
            let roster = try await membershipService.fetchMemberRoster(in: householdId, activeOnly: true)
                .filteredToActiveMembers(in: householdId)
            householdMembers = roster.memberships
            familyProfiles = Self.profilesEnsuringMembershipCoverage(
                profiles: roster.profiles,
                memberships: roster.memberships
            )
            LedgerWalletLoadLogger.step(
                .rosterEnd,
                token: token,
                source: source,
                householdId: householdId,
                detail: "members=\(householdMembers.count) profiles=\(familyProfiles.count)"
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                LedgerWalletLoadLogger.step(
                    .rosterCancel,
                    token: token,
                    source: source,
                    householdId: householdId,
                    detail: error.localizedDescription
                )
            } else {
                LedgerWalletLoadLogger.failure(
                    step: .rosterFail,
                    error: error,
                    token: token,
                    source: source,
                    householdId: householdId
                )
            }
            recordLoadError(error)
        }
    }

    /// 合并 membership 昵称，并为缺档案的 active membership 补 synthetic，避免垫付人列表缺当前用户。
    private static func profilesEnsuringMembershipCoverage(
        profiles: [FamilyProfile],
        memberships: [HouseholdMembership]
    ) -> [FamilyProfile] {
        var result = FamilyProfile.mergingMembershipRows(profiles, memberships: memberships)
        for membership in memberships {
            guard let profileId = membership.profileId else { continue }
            guard result.contains(where: { $0.id == profileId }) == false else { continue }
            let related = memberships.filter { $0.profileId == profileId }
            result.append(
                FamilyProfile.syntheticPlaceholder(
                    from: membership,
                    profileId: profileId,
                    relatedMemberships: related.isEmpty ? [membership] : related
                )
            )
        }
        return result.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    func loadLedgerData(force: Bool, loadToken: Int? = nil, source: String = "unspecified") async {
        guard let householdId = currentHouseholdId else { return }
        let token = loadToken ?? LedgerWalletLoadLogger.nextToken()
        let beforeCounts = Self.activeCategoryCounts(categories)
        LedgerWalletLoadLogger.step(
            .ledgerStart,
            token: token,
            source: source,
            householdId: householdId,
            detail: "force=\(force) loaded=\(loadedHouseholdId?.uuidString.lowercased() ?? "nil") before=\(LedgerWalletLoadLogger.categoryCounts(expense: beforeCounts.expense, income: beforeCounts.income, tags: tags.count, transactions: transactions.count))"
        )

        // 分类为空视为未就绪：禁止缓存命中，避免「补种失败一次 → 永远空白」
        if force == false,
           loadedHouseholdId == householdId,
           categories.contains(where: { $0.isDeleted == false }) {
            LedgerWalletLoadLogger.step(
                .ledgerCacheHit,
                token: token,
                source: source,
                householdId: householdId,
                detail: LedgerWalletLoadLogger.categoryCounts(
                    expense: beforeCounts.expense,
                    income: beforeCounts.income,
                    tags: tags.count,
                    transactions: transactions.count
                )
            )
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            LedgerWalletLoadLogger.step(
                .ensurePresetStart,
                token: token,
                source: source,
                householdId: householdId,
                detail: "pass=1"
            )
            try await ledgerService.ensurePresetCategories(in: householdId)
            LedgerWalletLoadLogger.step(
                .ensurePresetOk,
                token: token,
                source: source,
                householdId: householdId,
                detail: "pass=1"
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                LedgerWalletLoadLogger.step(
                    .ensurePresetCancel,
                    token: token,
                    source: source,
                    householdId: householdId,
                    detail: "pass=1 \(error.localizedDescription)"
                )
            } else {
                LedgerWalletLoadLogger.failure(
                    step: .ensurePresetFail,
                    error: error,
                    token: token,
                    source: source,
                    householdId: householdId,
                    detail: "pass=1"
                )
            }
            recordLoadError(error)
        }

        do {
            LedgerWalletLoadLogger.step(
                .payloadStart,
                token: token,
                source: source,
                householdId: householdId,
                detail: "pass=1"
            )
            try await reloadLedgerPayload(householdId: householdId)
            let afterPass1 = Self.activeCategoryCounts(categories)
            LedgerWalletLoadLogger.step(
                .payloadOk,
                token: token,
                source: source,
                householdId: householdId,
                detail: "pass=1 \(LedgerWalletLoadLogger.categoryCounts(expense: afterPass1.expense, income: afterPass1.income, tags: tags.count, transactions: transactions.count))"
            )

            // 成员端只能看到 income：若仍空，再补种并重拉一次（覆盖竞态 / 仅有支出分类的家庭）
            if visibleCategoriesNeedRetry {
                LedgerWalletLoadLogger.step(
                    .retryNeeded,
                    token: token,
                    source: source,
                    householdId: householdId,
                    detail: LedgerWalletLoadLogger.categoryCounts(
                        expense: afterPass1.expense,
                        income: afterPass1.income,
                        tags: tags.count,
                        transactions: transactions.count
                    )
                )
                do {
                    LedgerWalletLoadLogger.step(
                        .ensurePresetStart,
                        token: token,
                        source: source,
                        householdId: householdId,
                        detail: "pass=2"
                    )
                    try await ledgerService.ensurePresetCategories(in: householdId)
                    LedgerWalletLoadLogger.step(
                        .ensurePresetOk,
                        token: token,
                        source: source,
                        householdId: householdId,
                        detail: "pass=2"
                    )
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        LedgerWalletLoadLogger.step(
                            .ensurePresetCancel,
                            token: token,
                            source: source,
                            householdId: householdId,
                            detail: "pass=2 \(error.localizedDescription)"
                        )
                    } else {
                        LedgerWalletLoadLogger.failure(
                            step: .ensurePresetFail,
                            error: error,
                            token: token,
                            source: source,
                            householdId: householdId,
                            detail: "pass=2"
                        )
                    }
                    recordLoadError(error)
                }
                LedgerWalletLoadLogger.step(
                    .payloadStart,
                    token: token,
                    source: source,
                    householdId: householdId,
                    detail: "pass=2"
                )
                try await reloadLedgerPayload(householdId: householdId)
                let afterPass2 = Self.activeCategoryCounts(categories)
                LedgerWalletLoadLogger.step(
                    .payloadOk,
                    token: token,
                    source: source,
                    householdId: householdId,
                    detail: "pass=2 \(LedgerWalletLoadLogger.categoryCounts(expense: afterPass2.expense, income: afterPass2.income, tags: tags.count, transactions: transactions.count))"
                )
            }

            loadedHouseholdId = householdId
            let finalCounts = Self.activeCategoryCounts(categories)
            let countsDetail = LedgerWalletLoadLogger.categoryCounts(
                expense: finalCounts.expense,
                income: finalCounts.income,
                tags: tags.count,
                transactions: transactions.count
            )
            if categories.contains(where: { $0.isDeleted == false }) {
                errorMessage = nil
                LedgerWalletLoadLogger.step(
                    .ledgerEndOk,
                    token: token,
                    source: source,
                    householdId: householdId,
                    detail: countsDetail
                )
            } else {
                LedgerWalletLoadLogger.step(
                    .ledgerEndEmpty,
                    token: token,
                    source: source,
                    householdId: householdId,
                    detail: countsDetail
                )
            }
        } catch {
            if error is CancellationError || Task.isCancelled {
                LedgerWalletLoadLogger.step(
                    .payloadCancel,
                    token: token,
                    source: source,
                    householdId: householdId,
                    detail: error.localizedDescription
                )
            } else {
                LedgerWalletLoadLogger.failure(
                    step: .payloadFail,
                    error: error,
                    token: token,
                    source: source,
                    householdId: householdId
                )
            }
            recordLoadError(error)
            // 失败时不要记为已加载，下次进入可重试
            if error is CancellationError || Task.isCancelled {
                return
            }
            if loadedHouseholdId == householdId {
                loadedHouseholdId = nil
            }
        }
    }

    func loadInitialData(force: Bool, loadToken: Int? = nil, source: String = "unspecified") async {
        let token = loadToken ?? LedgerWalletLoadLogger.nextToken()
        await loadRoster(loadToken: token, source: source)
        await loadLedgerData(force: force, loadToken: token, source: source)
    }

    private static func activeCategoryCounts(_ categories: [ExpenseCategory]) -> (expense: Int, income: Int) {
        let active = categories.filter { $0.isDeleted == false }
        return (
            expense: active.filter { $0.type == .expense }.count,
            income: active.filter { $0.type == .income }.count
        )
    }

    /// 当前缓存里是否仍缺少可用分类（含「仅有支出、收入为空」对成员不可见的情况）。
    private var visibleCategoriesNeedRetry: Bool {
        let active = categories.filter { $0.isDeleted == false }
        if active.isEmpty { return true }
        // 若完全没有 income，成员页会空白；管理员也应有默认收入分类
        return active.contains(where: { $0.type == .income }) == false
    }

    private func reloadLedgerPayload(householdId: UUID) async throws {
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
            if let payerId = reportPayerFilterId, tx.payerIds.contains(payerId) == false {
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
        sumConverted(filteredTransactionsForReport.filter { $0.type == .expense })
    }

    var reportIncomeTotal: Double {
        sumConverted(filteredTransactionsForReport.filter { $0.type == .income })
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
                    amount: sumConverted(rows)
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
        sumConverted(dashboardTransactions.filter { $0.type == .expense })
    }

    var incomeTotalInPeriod: Double {
        sumConverted(dashboardTransactions.filter { $0.type == .income })
    }

    var dashboardTransactions: [LedgerTransaction] {
        transactions.filter {
            isInPeriod($0.transactionTime, period: ledgerGranularity, anchor: periodAnchor)
        }
    }

    func amount(for categoryId: UUID, type: LedgerEntryType) -> Double {
        sumConverted(
            dashboardTransactions.filter { $0.type == type && $0.categoryId == categoryId }
        )
    }

    /// 当前设置中的 Wallet 显示货币。
    var displayCurrencyCode: String {
        AppSettingsManager.shared.ledgerDisplayCurrency
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

    func updateTransaction(id: UUID, draft: LedgerTransactionDraft) async throws {
        let updated = try await ledgerService.updateTransaction(id: id, draft: draft)
        if let index = transactions.firstIndex(where: { $0.id == id }) {
            transactions[index] = updated
        } else {
            transactions.insert(updated, at: 0)
        }
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
    }

    func deleteTransaction(id: UUID) async throws {
        try await ledgerService.deleteTransaction(id: id)
        transactions.removeAll { $0.id == id }
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
    }

    /// 指定分类下的全部流水（按时间倒序）。
    func transactions(forCategoryId categoryId: UUID) -> [LedgerTransaction] {
        transactions
            .filter { $0.categoryId == categoryId }
            .sorted { $0.transactionTime > $1.transactionTime }
    }

    func entryCount(forCategoryId categoryId: UUID) -> Int {
        transactions(forCategoryId: categoryId).count
    }

    func totalAmount(forCategoryId categoryId: UUID) -> Double {
        sumConverted(transactions(forCategoryId: categoryId))
    }

    func convertedAmount(for transaction: LedgerTransaction) -> Double {
        ExchangeRateStore.shared.convert(
            amount: transaction.amount,
            from: transaction.currency,
            to: displayCurrencyCode
        )
    }

    func softDeleteCategory(_ category: ExpenseCategory) async throws {
        let householdId = currentHouseholdId
        let linkedCount = transactions.filter { $0.categoryId == category.id }.count

        LedgerCategoryDeleteLogger.step(
            .attempt,
            categoryId: category.id,
            categoryName: category.name,
            householdId: householdId,
            detail: "type=\(category.type.rawValue) is_preset=\(category.isPreset) linked_tx=\(linkedCount) tags=\(tags.filter { $0.categoryId == category.id }.count)"
        )

        guard canDeleteCategory(category) else {
            LedgerCategoryDeleteLogger.step(
                .blockedHasTransactions,
                categoryId: category.id,
                categoryName: category.name,
                householdId: householdId,
                detail: "linked_tx=\(linkedCount)"
            )
            AnalyticsManager.log(event: .ledgerCategoryDeleteBlocked(reason: "has_linked_transactions"))
            let blocked = LedgerCategoryMutationError.hasLinkedTransactions
            errorMessage = blocked.localizedDescription
            throw blocked
        }

        do {
            try await ledgerService.softDeleteCategory(id: category.id)
            categories.removeAll { $0.id == category.id }
            tags.removeAll { $0.categoryId == category.id }
            LedgerCategoryDeleteLogger.step(
                .localStateUpdated,
                categoryId: category.id,
                categoryName: category.name,
                householdId: householdId,
                detail: "remaining_categories=\(categories.count)"
            )
            LedgerCategoryDeleteLogger.step(
                .succeeded,
                categoryId: category.id,
                categoryName: category.name,
                householdId: householdId
            )
            AnalyticsManager.log(event: .ledgerCategoryDeleteSucceeded)
        } catch {
            LedgerCategoryDeleteLogger.failure(
                step: .failed,
                error: error,
                categoryId: category.id,
                categoryName: category.name,
                householdId: householdId
            )
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// 分类下若存在任一流水（含历史），不可删除。
    func canDeleteCategory(_ category: ExpenseCategory) -> Bool {
        transactions.contains { $0.categoryId == category.id } == false
    }

    func softDeleteTag(_ tag: CategoryTag) async throws {
        do {
            try await ledgerService.softDeleteTag(id: tag.id)
            tags.removeAll { $0.id == tag.id }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func addCategory(type: LedgerEntryType, name: String, icon: String) async throws -> ExpenseCategory? {
        guard let householdId = currentHouseholdId else { return nil }
        let created = try await ledgerService.createCategory(
            householdId: householdId,
            type: type,
            name: name,
            icon: icon,
            colorHex: "#007AFF"
        )
        categories.append(created)
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
        return created
    }

    func updateCategory(_ category: ExpenseCategory, name: String, icon: String, colorHex: String?) async throws {
        let updated = try await ledgerService.updateCategory(
            id: category.id,
            name: name,
            icon: icon,
            colorHex: colorHex
        )
        if let index = categories.firstIndex(where: { $0.id == updated.id }) {
            categories[index] = updated
        }
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

    /// `.task(id:)` / 切群组时取消进行中的请求属正常，勿当成加载失败展示。
    private func recordLoadError(_ error: Error) {
        if error is CancellationError { return }
        if Task.isCancelled { return }
        errorMessage = error.localizedDescription
    }

    private func sumConverted(_ rows: [LedgerTransaction]) -> Double {
        let target = displayCurrencyCode
        return rows.reduce(0) { partial, tx in
            partial + ExchangeRateStore.shared.convert(
                amount: tx.amount,
                from: tx.currency,
                to: target
            )
        }
    }

    private func periodTotals(
        for period: LedgerReportPeriod,
        anchor: Date
    ) -> (expense: Double, income: Double) {
        let rows = transactions.filter { isInPeriod($0.transactionTime, period: period, anchor: anchor) }
        let expense = sumConverted(rows.filter { $0.type == .expense })
        let income = sumConverted(rows.filter { $0.type == .income })
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
